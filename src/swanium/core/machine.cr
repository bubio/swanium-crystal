require "./cpu"
require "./interrupt_controller"
require "./timer"
require "./wonder_swan_bus"

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

      # Run one instruction, advance an optional hardware timer by its V30
      # cycle cost, and deliver the highest-priority enabled request at the
      # following instruction boundary.
      def step(bus : MemoryBus, timer : Timer? = nil, timer_vector : UInt8 = 0_u8) : UInt32
        cycles = @cpu.step(bus)
        if timer && timer.advance(cycles) > 0_u32
          @interrupts.request(InterruptSource::Timer)
        end

        if @cpu.flags.interrupt
          if source = @interrupts.next_pending?
            @interrupts.clear(source)
            cycles += @cpu.service_interrupt(bus, timer_vector)
          end
        end

        @cycles += cycles
        cycles
      end

      # Run one CPU instruction and acknowledge the WonderSwan bus's
      # highest-priority enabled request at the following instruction boundary.
      def step_wonder_swan(bus : WonderSwanBus) : UInt32
        cycles = @cpu.step(bus)
        if @cpu.flags.interrupt
          if vector = bus.pending_interrupt_vector?
            cycles += @cpu.service_interrupt(bus, vector)
          end
        end
        @cycles += cycles
        cycles
      end
    end
  end
end
