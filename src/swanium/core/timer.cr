module Swanium
  module Core
    # A clocked down-counter that returns the number of elapsed periods. Its
    # owner decides which interrupt source to request, keeping time deterministic.
    class Timer
      property enabled : Bool
      property reload : UInt32
      getter counter : UInt32

      def initialize(@reload : UInt32, @enabled = false)
        raise ArgumentError.new("timer reload must be positive") if @reload == 0_u32
        @counter = @reload
      end

      def reset : Nil
        @counter = @reload
      end

      def advance(cycles : UInt32) : UInt32
        return 0_u32 unless @enabled
        return 0_u32 if cycles == 0_u32

        if cycles < @counter
          @counter -= cycles
          return 0_u32
        end

        after_first = cycles - @counter
        expirations = 1_u32 + after_first // @reload
        remainder = after_first % @reload
        @counter = remainder == 0_u32 ? @reload : @reload - remainder
        expirations
      end
    end
  end
end
