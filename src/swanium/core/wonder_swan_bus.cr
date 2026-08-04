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

    # Bit positions in the WonderSwan INT_CAUSE / INT_ENABLE registers.
    # Higher-numbered sources have higher arbitration priority.
    enum WonderSwanInterrupt : UInt8
      SerialReceive = 0
      KeyPress      = 1
      Cartridge     = 2
      DmaComplete   = 3
      ScanlineMatch = 4
      VBlankTimer   = 5
      VBlank        = 6
      HBlankTimer   = 7
    end

    # Bit layout supplied by the platform layer to the keypad matrix.
    module WonderSwanKey
      Y1    = 1_u16 << 0
      Y2    = 1_u16 << 1
      Y3    = 1_u16 << 2
      Y4    = 1_u16 << 3
      X1    = 1_u16 << 4
      X2    = 1_u16 << 5
      X3    = 1_u16 << 6
      X4    = 1_u16 << 7
      Start = 1_u16 << 9
      A     = 1_u16 << 10
      B     = 1_u16 << 11
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
      getter keys : UInt16

      def initialize(@rom : Bytes = Bytes.new(0), save_ram_size : Int = 0, @model : WonderSwanModel = WonderSwanModel::Mono)
        raise ArgumentError.new("save RAM size must not be negative") if save_ram_size < 0
        @work_ram = Bytes.new(0x10000, 0_u8)
        @save_ram = Bytes.new(save_ram_size, 0_u8)
        @ports = Bytes.new(0x100, 0_u8)
        @linear_offset = 0xFF_u8
        @ram_bank = 0xFF_u8
        @rom_bank0 = 0xFF_u8
        @rom_bank1 = 0xFF_u8
        @keys = 0_u16
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
        when 0xC0_u8          then @linear_offset
        when 0xC1_u8          then @ram_bank
        when 0xC2_u8          then @rom_bank0
        when 0xC3_u8          then @rom_bank1
        when 0xA2_u8, 0xA3_u8 then @ports[port] & 0x0F_u8
        when 0xB0_u8          then @ports[port] & 0xF8_u8
        when 0xB5_u8          then scan_keys(@ports[port] & 0x70_u8)
        else                       @ports[port]
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
        when 0xA2_u8, 0xA3_u8
          @ports[port] = value & 0x0F_u8
        when 0xA4_u8, 0xA5_u8, 0xA6_u8, 0xA7_u8
          @ports[port] = value
          @ports[port &+ 4_u8] = value
        when 0xA8_u8..0xAB_u8, 0xB1_u8, 0xB4_u8
          # Hardware-maintained counters and INT_CAUSE are read-only.
        when 0xB0_u8
          @ports[port] = value & 0xF8_u8
        when 0xB2_u8
          @ports[port] = value
        when 0xB3_u8
          @ports[port] = value & 0xC4_u8
        when 0xB5_u8
          @ports[port] = value & 0x70_u8
        when 0xB6_u8
          @ports[port] = value
          @ports[0xB4] &= ~value
        else
          @ports[port] = value
        end
      end

      def request_interrupt(source : WonderSwanInterrupt) : Nil
        @ports[0xB4] |= (1_u8 << source.value) & @ports[0xB2]
      end

      # The platform layer supplies a complete input snapshot. Only a newly
      # pressed key raises the edge-triggered KeyPress source.
      def set_keys(keys : UInt16) : Nil
        request_interrupt(WonderSwanInterrupt::KeyPress) if (keys & ~@keys) != 0_u16
        @keys = keys
      end

      def pending_interrupt_vector? : UInt8?
        7.downto(0) do |priority|
          return @ports[0xB0] &+ priority.to_u8 if @ports[0xB4].bit(priority) == 1
        end
        nil
      end

      # Called by the LCD scheduler at the beginning of HBlank.
      def on_hblank : Nil
        counter = read_port_u16(0xA8_u8)
        return if counter == 0_u16 || (@ports[0xA2] & 0x01_u8) == 0_u8

        if counter == 1_u16
          request_interrupt(WonderSwanInterrupt::HBlankTimer)
          reload = (@ports[0xA2] & 0x02_u8) == 0_u8 ? 0_u16 : read_port_u16(0xA4_u8)
          write_counter(0xA8_u8, reload)
        else
          write_counter(0xA8_u8, counter - 1_u16)
        end
      end

      # Called by the LCD scheduler on the VBlank transition.
      def on_vblank : Nil
        request_interrupt(WonderSwanInterrupt::VBlank)
        counter = read_port_u16(0xAA_u8)
        return if counter == 0_u16 || (@ports[0xA2] & 0x04_u8) == 0_u8

        if counter == 1_u16
          request_interrupt(WonderSwanInterrupt::VBlankTimer)
          reload = (@ports[0xA2] & 0x08_u8) == 0_u8 ? 0_u16 : read_port_u16(0xA6_u8)
          write_counter(0xAA_u8, reload)
        else
          write_counter(0xAA_u8, counter - 1_u16)
        end
      end

      # The display controller updates this once per 256-cycle scanline.
      def set_current_scanline(line : UInt8) : Nil
        @ports[0x02] = line
        request_interrupt(WonderSwanInterrupt::ScanlineMatch) if line == @ports[0x03]
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

      private def read_port_u16(port : UInt8) : UInt16
        @ports[port].to_u16 | (@ports[port &+ 1_u8].to_u16 << 8)
      end

      private def write_counter(port : UInt8, value : UInt16) : Nil
        @ports[port] = (value & 0x00FF_u16).to_u8
        @ports[port &+ 1_u8] = (value >> 8).to_u8
      end

      private def scan_keys(selector : UInt8) : UInt8
        result = selector
        result |= (@keys & 0x000F_u16).to_u8 if (selector & 0x10_u8) != 0_u8
        result |= ((@keys >> 4) & 0x000F_u16).to_u8 if (selector & 0x20_u8) != 0_u8
        result |= ((@keys >> 8) & 0x000F_u16).to_u8 if (selector & 0x40_u8) != 0_u8
        result
      end
    end
  end
end
