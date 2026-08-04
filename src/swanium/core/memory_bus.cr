module Swanium
  module Core
    ADDRESS_MASK       = 0x0F_FFFF_u32
    ADDRESS_SPACE_SIZE =     0x10_0000

    # Platform-neutral, 20-bit V30 memory interface. The hardware map will
    # replace FlatMemory without changing CPU code.
    abstract class MemoryBus
      abstract def read_u8(address : UInt32) : UInt8
      abstract def write_u8(address : UInt32, value : UInt8) : Nil

      def read_u16(address : UInt32) : UInt16
        low = read_u8(address).to_u16
        high = read_u8(address &+ 1_u32).to_u16
        low | (high << 8)
      end

      def write_u16(address : UInt32, value : UInt16) : Nil
        write_u8(address, (value & 0x00FF_u16).to_u8)
        write_u8(address &+ 1_u32, (value >> 8).to_u8)
      end

      # Default open-bus I/O behavior keeps FlatMemory suitable for CPU specs.
      def read_io(port : UInt8) : UInt8
        0xFF_u8
      end

      def write_io(port : UInt8, value : UInt8) : Nil
      end

      # Some hardware I/O operations synchronously stall the V30. A bus
      # accumulates those costs while handling an instruction, and the CPU
      # consumes them before reporting that instruction's total cycle count.
      def consume_wait_cycles : UInt32
        0_u32
      end
    end

    class FlatMemory < MemoryBus
      def initialize
        @data = Bytes.new(ADDRESS_SPACE_SIZE, 0_u8)
      end

      def read_u8(address : UInt32) : UInt8
        @data[physical_address(address)]
      end

      def write_u8(address : UInt32, value : UInt8) : Nil
        @data[physical_address(address)] = value
      end

      def load(address : UInt32, values : Bytes) : Nil
        values.each_with_index do |value, index|
          write_u8(address &+ index.to_u32, value)
        end
      end

      private def physical_address(address : UInt32) : Int32
        (address & ADDRESS_MASK).to_i
      end
    end

    def self.linear_address(segment : UInt16, offset : UInt16) : UInt32
      ((segment.to_u32 << 4) + offset.to_u32) & ADDRESS_MASK
    end
  end
end
