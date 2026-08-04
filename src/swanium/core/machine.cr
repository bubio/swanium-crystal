module Swanium
  module Core
    # Platform-independent owner for emulation state. Hardware components will be
    # added here without exposing SDL, filesystem, or wall-clock dependencies.
    class Machine
      getter cycles : UInt64

      def initialize
        @cycles = 0_u64
      end

      def run_cycles(cycles : UInt32) : Nil
        @cycles += cycles
      end
    end
  end
end
