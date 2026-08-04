require "./cpu"
require "./interrupt_controller"
require "./timer"

module Swanium
  module Core
    # Platform-independent owner for emulation state. Hardware components will be
    # added here without exposing SDL, filesystem, or wall-clock dependencies.
    class Machine
      getter cycles : UInt64
      getter cpu : Cpu
      getter interrupts : InterruptController

      def initialize
        @cycles = 0_u64
        @cpu = Cpu.new
        @interrupts = InterruptController.new
      end

      def run_cycles(cycles : UInt32) : Nil
        @cycles += cycles
      end
    end
  end
end
