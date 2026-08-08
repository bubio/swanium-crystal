module Swanium
  module Core
    # Owns completed stereo PCM samples between the deterministic APU producer
    # and the frontend audio consumer.
    class PcmSampleBuffer
      def initialize(@initial_capacity : Int32 = 1024)
        @samples = Array(Int16).new(@initial_capacity)
      end

      def reset : Nil
        @samples.clear
      end

      def snapshot : Array(Int16)
        @samples.dup
      end

      def drain : Array(Int16)
        samples = @samples
        @samples = Array(Int16).new(@initial_capacity)
        samples
      end

      def append_stereo(left : Int16, right : Int16) : Nil
        @samples << left << right
      end

      def append_silence(frames : UInt32) : Nil
        frames.times { append_stereo(0_i16, 0_i16) }
      end

      def save_state(io : IO) : Nil
        io.write_bytes(@samples.size.to_u32, IO::ByteFormat::LittleEndian)
        @samples.each { |sample| io.write_bytes(sample, IO::ByteFormat::LittleEndian) }
      end

      def load_state(io : IO) : Nil
        sample_count = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        raise ArgumentError.new("invalid buffered PCM length") if sample_count > 1_000_000_u32
        @samples = Array(Int16).new(sample_count.to_i) do
          io.read_bytes(Int16, IO::ByteFormat::LittleEndian)
        end
      end
    end
  end
end
