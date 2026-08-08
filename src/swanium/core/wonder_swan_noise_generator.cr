module Swanium
  module Core
    # Models the cartridge-visible WonderSwan noise LFSR and its audible
    # channel-four output.
    class WonderSwanNoiseGenerator
      getter output : UInt8

      def initialize
        @lfsr = 0_u16
        @counter = 0_u16
        @output = 0_u8
      end

      def reset : Nil
        @lfsr = 0_u16
        @counter = 0_u16
        @output = 0_u8
      end

      def reset_lfsr(ports : Bytes) : Nil
        @lfsr = 0_u16
        @output = 0_u8
        @counter = 2048_u16 - pitch(ports)
        ports[0x8E] &= 0xF7_u8
        ports[0x92] = 0_u8
        ports[0x93] = 0_u8
      end

      def step(ports : Bytes, color_hardware : Bool) : Nil
        noise = ports[0x8E]
        if (noise & 0x08_u8) != 0_u8
          reset_lfsr(ports)
          return
        end
        return if (noise & 0x10_u8) == 0_u8
        return unless color_hardware || (ports[0x90] & 0x88_u8) == 0x88_u8

        @counter &-= 1_u16 if @counter > 0_u16
        return unless @counter == 0_u16

        taps = StaticArray[14_u8, 10_u8, 13_u8, 4_u8, 8_u8, 6_u8, 9_u8, 11_u8]
        tap = taps[(noise & 0x07_u8).to_i]
        feedback = 1_u16 ^ ((@lfsr >> 7) & 1_u16) ^ ((@lfsr >> tap) & 1_u16)
        @lfsr = ((@lfsr << 1) | feedback) & 0x7FFF_u16
        @output = (@lfsr & 1_u16) == 0_u16 ? 0_u8 : 0x0F_u8
        @counter = 2048_u16 - pitch(ports)
        ports[0x92] = (@lfsr & 0xFF_u16).to_u8
        ports[0x93] = (@lfsr >> 8).to_u8
      end

      def save_state(io : IO) : Nil
        io.write_bytes(@lfsr, IO::ByteFormat::LittleEndian)
        io.write_bytes(@counter, IO::ByteFormat::LittleEndian)
        io.write_byte(@output)
      end

      def load_state(io : IO) : Nil
        @lfsr = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
        @counter = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
        @output = io.read_byte || raise IO::EOFError.new
      end

      private def pitch(ports : Bytes) : UInt16
        (ports[0x86].to_u16 | (ports[0x87].to_u16 << 8)) & 0x07FF_u16
      end
    end
  end
end
