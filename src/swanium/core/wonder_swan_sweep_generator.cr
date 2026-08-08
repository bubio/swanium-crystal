module Swanium
  module Core
    # Owns channel-three pitch sweep timing and register updates.
    class WonderSwanSweepGenerator
      def initialize
        @counter = 0_u32
        @step = 0_u8
        @fast_primed = false
      end

      def reset : Nil
        @counter = 0_u32
        @step = 0_u8
        @fast_primed = false
      end

      # Fast paths that skip sweep timing must clear its delayed first tick.
      def deactivate : Nil
        @fast_primed = false
      end

      def step(ports : Bytes) : Nil
        unless (ports[0x90] & 0x44_u8) == 0x44_u8
          @fast_primed = false
          return
        end

        fast = (ports[0x95] & 0x02_u8) != 0_u8
        if fast
          unless @fast_primed
            @fast_primed = true
            return
          end
        else
          @fast_primed = false
        end
        @counter += 1_u32
        return if @counter <= (fast ? 0_u32 : 8192_u32)
        @counter = 0_u32
        if @step != 0_u8
          @step &-= 1_u8
          return
        end
        @step = ports[0x8D] & 0x1F_u8
        @step &-= 1_u8 if @step > 0_u8

        pitch = pitch(ports).to_i32 + ports[0x8C].unsafe_as(Int8).to_i32
        pitch = pitch > 0x7FF ? 0 : pitch < 0 ? 0x7FF : pitch
        ports[0x84] = (pitch & 0xFF).to_u8
        ports[0x85] = ((pitch >> 8) & 0x07).to_u8
      end

      def save_state(io : IO) : Nil
        io.write_bytes(@counter, IO::ByteFormat::LittleEndian)
        io.write_byte(@step)
        io.write_byte(@fast_primed ? 1_u8 : 0_u8)
      end

      def load_state(io : IO) : Nil
        @counter = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        @step = io.read_byte || raise IO::EOFError.new
        @fast_primed = (io.read_byte || raise IO::EOFError.new) != 0_u8
      end

      private def pitch(ports : Bytes) : UInt16
        (ports[0x84].to_u16 | (ports[0x85].to_u16 << 8)) & 0x07FF_u16
      end
    end
  end
end
