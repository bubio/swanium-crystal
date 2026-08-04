require "./memory_bus"

module Swanium
  module Core
    # Memory-window capability of the WonderSwan family. Color and Crystal
    # expose all 64 KiB of internal RAM; the original model exposes 16 KiB.
    enum WonderSwanModel
      Mono
      Color
      Crystal

      def color? : Bool
        self != Mono
      end
    end

    # Platform-neutral first hardware bus. It models the CPU-visible address
    # map and cartridge bank registers while PPU/APU/DMA devices are added on
    # top through the same I/O port file.
    class WonderSwanBus < MemoryBus
      OPEN_BUS = 0xFF_u8

      getter model : WonderSwanModel
      getter work_ram : Bytes
      getter save_ram : Bytes
      getter ports : Bytes

      def initialize(@rom : Bytes = Bytes.new(0), save_ram_size : Int = 0, @model : WonderSwanModel = WonderSwanModel::Mono)
        raise ArgumentError.new("save RAM size must not be negative") if save_ram_size < 0
        @work_ram = Bytes.new(0x10000, 0_u8)
        @save_ram = Bytes.new(save_ram_size, 0_u8)
        @ports = Bytes.new(0x100, 0_u8)
        @linear_offset = 0xFF_u8
        @ram_bank = 0xFF_u8
        @rom_bank0 = 0xFF_u8
        @rom_bank1 = 0xFF_u8
      end

      def read_u8(address : UInt32) : UInt8
        address = address & ADDRESS_MASK
        case address
        when 0x00000_u32..0x0FFFF_u32 then read_work_ram(address)
        when 0x10000_u32..0x1FFFF_u32 then read_save_ram(address)
        when 0x20000_u32..0x2FFFF_u32 then read_rom_bank(@rom_bank0, address)
        when 0x30000_u32..0x3FFFF_u32 then read_rom_bank(@rom_bank1, address)
        else                               read_linear_rom(address)
        end
      end

      def write_u8(address : UInt32, value : UInt8) : Nil
        address &= ADDRESS_MASK
        case address
        when 0x00000_u32..0x0FFFF_u32 then write_work_ram(address, value)
        when 0x10000_u32..0x1FFFF_u32 then write_save_ram(address, value)
        end
      end

      def read_io(port : UInt8) : UInt8
        # Hardware-only/read-only ports will gain device-specific handlers;
        # unknown ports intentionally retain open-bus behavior.
        case port
        when 0xC0_u8 then @linear_offset
        when 0xC1_u8 then @ram_bank
        when 0xC2_u8 then @rom_bank0
        when 0xC3_u8 then @rom_bank1
        else              @ports[port]
        end
      end

      def write_io(port : UInt8, value : UInt8) : Nil
        case port
        when 0xC0_u8
          @linear_offset = value & 0x3F_u8
          @ports[port] = @linear_offset
        when 0xC1_u8
          @ram_bank = value
          @ports[port] = value
        when 0xC2_u8
          @rom_bank0 = value
          @ports[port] = value
        when 0xC3_u8
          @rom_bank1 = value
          @ports[port] = value
        else
          @ports[port] = value
        end
      end

      private def read_work_ram(address : UInt32) : UInt8
        return OPEN_BUS if address > 0x03FFF_u32 && !@model.color?
        @work_ram[address.to_i]
      end

      private def write_work_ram(address : UInt32, value : UInt8) : Nil
        return if address > 0x03FFF_u32 && !@model.color?
        @work_ram[address.to_i] = value
      end

      private def read_save_ram(address : UInt32) : UInt8
        return OPEN_BUS if @save_ram.empty?
        @save_ram[bank_index(@ram_bank, address, @save_ram.size)]
      end

      private def write_save_ram(address : UInt32, value : UInt8) : Nil
        return if @save_ram.empty?
        @save_ram[bank_index(@ram_bank, address, @save_ram.size)] = value
      end

      private def read_rom_bank(bank : UInt8, address : UInt32) : UInt8
        return OPEN_BUS if @rom.empty?
        @rom[bank_index(bank, address, @rom.size)]
      end

      private def read_linear_rom(address : UInt32) : UInt8
        return OPEN_BUS if @rom.empty?
        index = ((@linear_offset.to_u64 << 20) | address.to_u64) % @rom.size.to_u64
        @rom[index.to_i]
      end

      private def bank_index(bank : UInt8, address : UInt32, size : Int) : Int
        (((bank.to_u64 << 16) | (address & 0xFFFF_u32).to_u64) % size.to_u64).to_i
      end
    end
  end
end
