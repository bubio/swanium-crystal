require "./flags"
require "./memory_bus"
require "./registers"

module Swanium
  module Core
    # Minimal V30 execution state. Decoder and opcode execution will build on
    # this deterministic fetch/reset boundary.
    class Cpu
      property registers : Registers
      property flags : Flags
      property halted : Bool

      def initialize
        @registers = Registers.new
        @flags = Flags.new
        @halted = false
      end

      def reset(code_segment : UInt16, instruction_pointer : UInt16) : Nil
        @registers = Registers.new
        @flags = Flags.new
        @registers.cs = code_segment
        @registers.ip = instruction_pointer
        @registers.sp = 0x2000_u16
        @halted = false
      end

      def fetch_u8(bus : MemoryBus) : UInt8
        address = Core.linear_address(@registers.cs, @registers.ip)
        value = bus.read_u8(address)
        @registers.ip &+= 1_u16
        value
      end

      def fetch_u16(bus : MemoryBus) : UInt16
        low = fetch_u8(bus).to_u16
        high = fetch_u8(bus).to_u16
        low | (high << 8)
      end
    end
  end
end
