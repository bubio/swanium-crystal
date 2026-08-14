module Swanium
  module Core
    # Channel-two streamed PCM interpolation and stereo routing state.
    class WonderSwanVoiceChannel
      def initialize
        @previous = 0_i32
        @level = 0_i32
      end

      def reset : Nil
        @previous = 0_i32
        @level = 0_i32
      end

      def write(sample : UInt8) : Nil
        current = sample.to_i32 - 0x80
        @level = (current + @previous) // 2
        @previous = current
      end

      # Resets the analog interpolation state when voice mode is disabled,
      # matching the APU's sample-boundary behaviour.
      def mix(ports : Bytes, scale : Int32) : Tuple(Int32, Int32)
        unless (ports[0x90] & 0x20_u8) != 0_u8
          reset
          return {0_i32, 0_i32}
        end

        voice = @level * scale * 2
        volume = ports[0x94]
        left = (volume & 0x04_u8) != 0_u8 ? voice : (volume & 0x08_u8) != 0_u8 ? voice >> 1 : 0_i32
        right = (volume & 0x01_u8) != 0_u8 ? voice : (volume & 0x02_u8) != 0_u8 ? voice >> 1 : 0_i32
        {left, right}
      end

      def save_state(io : IO) : Nil
        io.write_bytes(@previous, IO::ByteFormat::LittleEndian)
        io.write_bytes(@level, IO::ByteFormat::LittleEndian)
      end

      def load_state(io : IO) : Nil
        @previous = io.read_bytes(Int32, IO::ByteFormat::LittleEndian)
        @level = io.read_bytes(Int32, IO::ByteFormat::LittleEndian)
      end
    end
  end
end
