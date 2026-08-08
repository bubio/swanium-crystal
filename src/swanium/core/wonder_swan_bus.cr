require "./memory_bus"
require "./apu"
require "./cartridge"
require "./rtc"

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

      # SDMA feeds the Color/Crystal voice channel at a programmable cadence.
      # Keep its latched transfer state separate from the CPU-visible ports so
      # a save state can resume a transfer partway through its sample period.
      private struct SdmaState
        property source : UInt32
        property counter : UInt32
        property source_shadow : UInt32
        property counter_shadow : UInt32
        property clock : UInt32
        property running : Bool

        def initialize(@source = 0_u32, @counter = 0_u32, @source_shadow = 0_u32,
                       @counter_shadow = 0_u32, @clock = 0_u32, @running = false)
        end
      end

      getter model : WonderSwanModel
      getter work_ram : Bytes
      getter save_ram : Bytes
      getter ports : Bytes
      getter keys : UInt16
      getter linear_offset : UInt8
      getter ram_bank : UInt8
      getter ram_bank_hi : UInt8
      getter rom_bank0 : UInt8
      getter rom_bank0_hi : UInt8
      getter rom_bank1 : UInt8
      getter rom_bank1_hi : UInt8
      getter cartridge_header : CartridgeHeader?

      def initialize(@rom : Bytes = Bytes.new(0), save_ram_size : Int = 0, @model : WonderSwanModel = WonderSwanModel::Mono,
                     @cartridge_header : CartridgeHeader? = nil, @save_ram_mapped : Bool = true)
        raise ArgumentError.new("save RAM size must not be negative") if save_ram_size < 0
        @work_ram = Bytes.new(0x10000, 0_u8)
        @save_ram = Bytes.new(save_ram_size, 0_u8)
        if @cartridge_header && @cartridge_header.not_nil!.save_medium.in?(SaveMedium::Eeprom128B, SaveMedium::Eeprom1KiB, SaveMedium::Eeprom2KiB)
          @save_ram.fill(0xFF_u8)
          @eeprom = CartridgeEeprom.new(@save_ram, eeprom_address_bits(@save_ram.size))
        else
          @eeprom = nil
        end
        @rtc = @cartridge_header.try(&.rtc) ? Rtc.new : nil
        @ports = Bytes.new(0x100, 0_u8)
        @linear_offset = 0xFF_u8
        @ram_bank = 0xFF_u8
        @ram_bank_hi = 0xFF_u8
        @rom_bank0 = 0xFF_u8
        @rom_bank0_hi = 0xFF_u8
        @rom_bank1 = 0xFF_u8
        @rom_bank1_hi = 0xFF_u8
        @keys = 0_u16
        @voice_writes = [] of UInt8
        @sdma = SdmaState.new
        @ports[0x9E] = 0x03_u8
        @pending_wait_cycles = 0_u32
      end

      def self.from_cartridge(cartridge : CartridgeImage) : WonderSwanBus
        header = cartridge.header
        # This product intentionally emulates SwanCrystal for every cartridge.
        # The footer's color-required bit describes the minimum console, not
        # the selected host hardware; Mono and Color cartridges run through
        # SwanCrystal's backwards-compatible hardware path.
        new(cartridge.rom, save_ram_size: header.save_medium.size, model: WonderSwanModel::Crystal,
          cartridge_header: header, save_ram_mapped: header.save_medium.sram?)
      end

      def replace_save_ram(data : Bytes) : Nil
        raise ArgumentError.new("save data size does not match cartridge") unless data.size == @save_ram.size
        @save_ram.copy_from(data)
      end

      def consume_voice_writes : Array(UInt8)
        writes = @voice_writes
        @voice_writes = [] of UInt8
        writes
      end

      def has_rtc? : Bool
        !@rtc.nil?
      end

      def tick_rtc(cycles : UInt32) : Nil
        @rtc.try(&.tick(cycles))
      end

      def set_rtc_datetime(year : UInt8, month : UInt8, day : UInt8, weekday : UInt8,
                           hour : UInt8, minute : UInt8, second : UInt8) : Nil
        @rtc.try(&.set_datetime(year, month, day, weekday, hour, minute, second))
      end

      def save_rtc_state(io : IO) : Nil
        io.write_byte(has_rtc? ? 1_u8 : 0_u8)
        @rtc.try(&.save_state(io))
      end

      def load_rtc_state(io : IO) : Nil
        present = io.read_byte || raise IO::EOFError.new
        raise ArgumentError.new("save state RTC presence does not match cartridge") unless (present != 0_u8) == has_rtc?
        @rtc.try(&.load_state(io))
      end

      def tick_sound(cycles : UInt32, apu : Apu) : Nil
        unless @model.color? && sdma_enabled?
          @sdma.running = false
          @sdma.clock = 0_u32
          apu.tick(cycles, @work_ram, @ports, color_rendering_enabled?)
          return
        end

        cycles.times do
          tick_sdma_cycle(apu)
          apu.tick(1_u32, @work_ram, @ports, color_rendering_enabled?)
        end
      end

      def save_sdma_state(io : IO) : Nil
        io.write_bytes(@sdma.source, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.counter, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.source_shadow, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.counter_shadow, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.clock, IO::ByteFormat::LittleEndian)
        io.write_byte(@sdma.running ? 1_u8 : 0_u8)
      end

      def load_sdma_state(io : IO) : Nil
        @sdma = SdmaState.new(
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          (io.read_byte || raise IO::EOFError.new) != 0_u8
        )
      end

      def read_u8(address : UInt32) : UInt8
        address = address & ADDRESS_MASK
        case address
        when 0x00000_u32..0x0FFFF_u32 then read_work_ram(address)
        when 0x10000_u32..0x1FFFF_u32 then read_save_ram(address)
        when 0x20000_u32..0x2FFFF_u32 then read_rom_bank(@rom_bank0, @rom_bank0_hi, address)
        when 0x30000_u32..0x3FFFF_u32 then read_rom_bank(@rom_bank1, @rom_bank1_hi, address)
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
        when 0x00_u8                   then @ports[port] & 0x3F_u8
        when 0x01_u8                   then color_rendering_enabled? ? @ports[port] : @ports[port] & 0x07_u8
        when 0x04_u8                   then @ports[port] & (color_rendering_enabled? ? 0x3F_u8 : 0x1F_u8)
        when 0x05_u8                   then @ports[port] & 0x7F_u8
        when 0x07_u8                   then color_rendering_enabled? ? @ports[port] : @ports[port] & 0x77_u8
        when 0x15_u8                   then @ports[port] & 0x3F_u8
        when 0x19_u8, 0x1B_u8          then 0_u8
        when 0x20_u8..0x3F_u8          then @ports[port] & mono_palette_port_mask(port)
        when 0x40_u8, 0x44_u8, 0x46_u8 then @ports[port] & 0xFE_u8
        when 0x42_u8                   then @ports[port] & 0x0F_u8
        when 0x43_u8, 0x49_u8          then 0_u8
        when 0x48_u8
          value = @ports[port] & 0xC0_u8
          @ports[port] = 0_u8
          value
        when 0x4C_u8, 0x50_u8                   then @ports[port] & 0x0F_u8
        when 0x4D_u8, 0x51_u8, 0x53_u8..0x5F_u8 then 0_u8
        when 0x61_u8, 0x63_u8                   then 0_u8
        when 0x64_u8..0x69_u8                   then 0_u8
        when 0x6A_u8                            then @ports[port]
        when 0x6B_u8                            then @ports[port] & 0x6F_u8
        when 0x6C_u8..0x7F_u8                   then 0_u8
        when 0x81_u8, 0x83_u8, 0x85_u8, 0x87_u8 then @ports[port] & 0x07_u8
        when 0x8D_u8                            then @ports[port] & 0x1F_u8
        when 0x8E_u8                            then @ports[port] & 0x17_u8
        when 0x90_u8                            then @ports[port] & 0xEF_u8
        when 0x91_u8                            then @ports[port] & 0x8F_u8
        when 0x92_u8, 0x93_u8                   then @ports[port]
        when 0x94_u8                            then @ports[port] & 0x0F_u8
        when 0x96_u8..0x9B_u8                   then @ports[port]
        when 0x9E_u8                            then @ports[port] & 0x03_u8
        when 0x9F_u8, 0xA1_u8                   then 0_u8
        when 0xC4_u8, 0xC5_u8, 0xC6_u8, 0xC7_u8 then @eeprom ? @ports[port] : OPEN_BUS
        when 0xC8_u8                            then @eeprom ? 0x02_u8 | (@ports[port] & 0x01_u8) : OPEN_BUS
        when 0x52_u8                            then @ports[port] & 0xDF_u8
        when 0xCA_u8                            then @rtc ? @rtc.not_nil!.read_command : Rtc::OPEN_BUS
        when 0xCB_u8                            then @rtc ? @rtc.not_nil!.read_data : Rtc::OPEN_BUS
        when 0xC0_u8                            then @linear_offset
        when 0xC1_u8                            then @ram_bank
        when 0xC2_u8                            then @rom_bank0
        when 0xC3_u8                            then @rom_bank1
        when 0xD0_u8                            then mapper_2003? ? @ram_bank : OPEN_BUS
        when 0xD1_u8                            then mapper_2003? ? @ram_bank_hi : OPEN_BUS
        when 0xD2_u8                            then mapper_2003? ? @rom_bank0 : OPEN_BUS
        when 0xD3_u8                            then mapper_2003? ? @rom_bank0_hi : OPEN_BUS
        when 0xD4_u8                            then mapper_2003? ? @rom_bank1 : OPEN_BUS
        when 0xD5_u8                            then mapper_2003? ? @rom_bank1_hi : OPEN_BUS
        when 0xA2_u8, 0xA3_u8                   then @ports[port] & 0x0F_u8
        when 0xAD_u8..0xAF_u8                   then 0_u8
        when 0xA0_u8                            then (@model.color? ? 0x87_u8 : 0x86_u8) | (@ports[port] & 0x08_u8)
        when 0xB0_u8
          @model == WonderSwanModel::Mono ? (@ports[port] & 0xF8_u8) | highest_pending_bit : @ports[port] & 0xF8_u8
        when 0xB4_u8
          refresh_serial_tx_irq
          cause = @ports[port]
          # Key, scanline and timer sources are edge-triggered and clear on
          # INT_CAUSE reads. Serial/cartridge/DMA remain level-latched.
          @ports[port] &= 0x0D_u8
          cause
        when 0xB6_u8 then 0_u8
        when 0xB7_u8
          value = @ports[port] & 0x10_u8
          @ports[port] = value
          value
        when 0xB5_u8 then scan_keys(@ports[port] & 0x70_u8)
        else              @ports[port]
        end
      end

      def write_io(port : UInt8, value : UInt8) : Nil
        case port
        when 0x00_u8
          @ports[port] = value & 0x3F_u8
        when 0x02_u8
          # LCD line is maintained by the display scheduler.
        when 0x04_u8
          @ports[port] = value & (color_rendering_enabled? ? 0x3F_u8 : 0x1F_u8)
        when 0x05_u8
          @ports[port] = value & 0x7F_u8
        when 0x07_u8
          @ports[port] = value & (color_rendering_enabled? ? 0xFF_u8 : 0x77_u8)
        when 0x15_u8
          @ports[port] = value & 0x3F_u8
        when 0x19_u8, 0x1B_u8
        when 0x20_u8..0x3F_u8
          @ports[port] = value & mono_palette_port_mask(port)
        when 0x64_u8..0x67_u8
          write_hypervoice_direct(port, value) if @model.color?
        when 0x68_u8
          @ports[port] = value if @model.color?
        when 0x69_u8
          write_hypervoice_data_latch(value) if @model.color?
        when 0x6A_u8
          @ports[port] = value if @model.color?
        when 0x6B_u8
          @ports[port] = value & 0x6F_u8 if @model.color?
        when 0x6C_u8..0x7F_u8
        when 0x81_u8, 0x83_u8, 0x85_u8, 0x87_u8
          @ports[port] = value & 0x07_u8
        when 0x8D_u8
          @ports[port] = value & 0x1F_u8
        when 0x8E_u8
          @ports[port] = value & 0x1F_u8
        when 0x90_u8
          @ports[port] = value & 0xEF_u8
        when 0x91_u8
          @ports[port] = value & 0x8F_u8
        when 0x92_u8, 0x93_u8, 0x96_u8..0x9B_u8, 0x9F_u8, 0xA1_u8
        when 0x94_u8
          @ports[port] = value & 0x0F_u8
        when 0x9E_u8
          @ports[port] = value & 0x03_u8
        when 0xC4_u8..0xC7_u8
          @ports[port] = value
        when 0xC8_u8
          eeprom_control(value) if @eeprom
        when 0xCA_u8
          @rtc.try(&.write_command(value))
        when 0xCB_u8
          @rtc.try(&.write_data(value))
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
        when 0xD0_u8
          @ram_bank = value if mapper_2003?
        when 0xD1_u8
          @ram_bank_hi = value if mapper_2003?
        when 0xD2_u8
          @rom_bank0 = value if mapper_2003?
        when 0xD3_u8
          @rom_bank0_hi = value if mapper_2003?
        when 0xD4_u8
          @rom_bank1 = value if mapper_2003?
        when 0xD5_u8
          @rom_bank1_hi = value if mapper_2003?
        when 0x89_u8
          @ports[port] = value
          @voice_writes << value if (@ports[0x90] & 0x20_u8) != 0_u8
        when 0xA2_u8, 0xA3_u8
          @ports[port] = value & 0x0F_u8
        when 0x61_u8, 0x63_u8
          # Unused system-control holes read as zero on SwanCrystal.
        when 0x40_u8..0x5F_u8
          write_dma_io(port, value) if color_rendering_enabled?
        when 0xA4_u8, 0xA5_u8, 0xA6_u8, 0xA7_u8
          @ports[port] = value
          @ports[port &+ 4_u8] = value
        when 0xA8_u8..0xAB_u8, 0xAD_u8..0xAF_u8, 0xB1_u8, 0xB4_u8
          # Hardware-maintained counters and INT_CAUSE are read-only.
        when 0xB0_u8
          @ports[port] = value & 0xF8_u8
        when 0xB2_u8
          @ports[port] = value
          refresh_serial_tx_irq
        when 0xB3_u8
          @ports[port] = value & 0xC4_u8
          refresh_serial_tx_irq
        when 0xB5_u8
          @ports[port] = value & 0x70_u8
        when 0xB6_u8
          @ports[port] = value
          @ports[0xB4] &= ~value
        else
          @ports[port] = value
        end
      end

      def consume_wait_cycles : UInt32
        cycles = @pending_wait_cycles
        @pending_wait_cycles = 0_u32
        cycles
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
        return if counter == 0_u16

        # The final count can still latch when its interrupt source is enabled,
        # even if the HBlank timer enable bit was cleared. This hardware quirk
        # is observable by WSHWTest and is relied upon by timer wait loops.
        enabled = (@ports[0xA2] & 0x01_u8) != 0_u8
        irq_enabled = (@ports[0xB2] & (1_u8 << WonderSwanInterrupt::HBlankTimer.value)) != 0_u8
        return unless enabled || (counter == 1_u16 && irq_enabled)

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

      def restore_state(work_ram : Bytes, save_ram : Bytes, ports : Bytes, keys : UInt16,
                        linear_offset : UInt8, ram_bank : UInt8, ram_bank_hi : UInt8,
                        rom_bank0 : UInt8, rom_bank0_hi : UInt8, rom_bank1 : UInt8, rom_bank1_hi : UInt8) : Nil
        raise ArgumentError.new("state RAM size does not match machine") unless work_ram.size == @work_ram.size && save_ram.size == @save_ram.size
        raise ArgumentError.new("state port file has invalid size") unless ports.size == @ports.size
        @work_ram.copy_from(work_ram)
        @save_ram.copy_from(save_ram)
        @ports.copy_from(ports)
        @keys = keys
        @linear_offset = linear_offset
        @ram_bank = ram_bank
        @ram_bank_hi = ram_bank_hi
        @rom_bank0 = rom_bank0
        @rom_bank0_hi = rom_bank0_hi
        @rom_bank1 = rom_bank1
        @rom_bank1_hi = rom_bank1_hi
        @sdma = SdmaState.new
        @pending_wait_cycles = 0_u32
      end

      private def read_work_ram(address : UInt32) : UInt8
        return OPEN_BUS if address > 0x03FFF_u32 && !@model.color?
        @work_ram[address.to_i]
      end

      # Color GDMA performs its complete burst at the control-port write, and
      # stalls the CPU for the transfer. It only writes internal RAM; SRAM
      # sources abort the burst as on the hardware.
      private def write_dma_io(port : UInt8, value : UInt8) : Nil
        case port
        when 0x40_u8, 0x44_u8, 0x46_u8
          @ports[port] = value & 0xFE_u8
        when 0x42_u8
          @ports[port] = value & 0x0F_u8
        when 0x4C_u8, 0x50_u8
          @ports[port] = value & 0x0F_u8
        when 0x43_u8, 0x49_u8, 0x4D_u8, 0x51_u8, 0x53_u8..0x5F_u8
          # Reserved / read-only holes.
        when 0x48_u8
          @ports[port] = value
          @pending_wait_cycles += execute_gdma
        else
          @ports[port] = value
        end
      end

      private def execute_gdma : UInt32
        return 0_u32 if (@ports[0x48] & 0x80_u8) == 0_u8

        source = read_port_u16(0x40_u8).to_u32 | ((@ports[0x42] & 0x0F_u8).to_u32 << 16)
        destination = read_port_u16(0x44_u8).to_u32
        remaining = read_port_u16(0x46_u8)
        if remaining == 0_u16
          @ports[0x48] &= 0x7F_u8
          return 0_u32
        end

        decrement = (@ports[0x48] & 0x40_u8) != 0_u8
        transferred = 0_u32
        while remaining > 0_u16
          break if gdma_source_blocked?(source)

          write_work_ram(destination & 0xFFFF_u32, read_u8(source))
          if decrement
            source &-= 1_u32
            destination &-= 1_u32
          else
            source &+= 1_u32
            destination &+= 1_u32
          end
          remaining &-= 1_u16
          transferred += 1_u32
        end

        write_port_u16(0x40_u8, (source & 0xFFFF_u32).to_u16)
        @ports[0x42] = ((source >> 16) & 0x0F_u32).to_u8
        write_port_u16(0x44_u8, (destination & 0xFFFF_u32).to_u16)
        write_port_u16(0x46_u8, remaining)
        @ports[0x48] &= 0x7F_u8
        request_interrupt(WonderSwanInterrupt::DmaComplete)
        transferred == 0_u32 ? 0_u32 : 5_u32 + transferred
      end

      private def sdma_enabled? : Bool
        (@ports[0x52] & 0x80_u8) != 0_u8
      end

      private def tick_sdma_cycle(apu : Apu) : Nil
        return unless start_sdma_if_needed

        @sdma.clock += 1_u32
        period = 128_u32 * sdma_rate
        return if @sdma.clock < period

        @sdma.clock -= period
        transfer_sdma_byte(apu)
      end

      private def start_sdma_if_needed : Bool
        return true if @sdma.running

        counter = sdma_counter_from_ports
        if counter == 0_u32
          @ports[0x52] &= 0x7F_u8
          return false
        end

        @sdma.source = sdma_source_from_ports
        @sdma.counter = counter
        @sdma.source_shadow = @sdma.source
        @sdma.counter_shadow = counter
        @sdma.clock = 0_u32
        @sdma.running = true
        true
      end

      private def transfer_sdma_byte(apu : Apu) : Nil
        control = @ports[0x52]
        if (control & 0x04_u8) != 0_u8
          write_sdma_voice(0_u8, apu)
          return
        end

        write_sdma_voice(read_u8(@sdma.source), apu)
        if (control & 0x40_u8) != 0_u8
          @sdma.source = (@sdma.source &- 1_u32) & ADDRESS_MASK
        else
          @sdma.source = (@sdma.source &+ 1_u32) & ADDRESS_MASK
        end
        @sdma.counter = (@sdma.counter &- 1_u32) & ADDRESS_MASK

        if @sdma.counter == 0_u32
          if (control & 0x08_u8) != 0_u8
            @sdma.source = @sdma.source_shadow
            @sdma.counter = @sdma.counter_shadow
          else
            @ports[0x52] &= 0x7F_u8
            @sdma.running = false
            @sdma.clock = 0_u32
          end
        end
        write_sdma_ports
      end

      private def write_sdma_voice(value : UInt8, apu : Apu) : Nil
        @ports[0x89] = value
        apu.write_voice(value) if (@ports[0x90] & 0x20_u8) != 0_u8
      end

      private def sdma_rate : UInt32
        case @ports[0x52] & 0x03_u8
        when 0_u8 then 6_u32
        when 1_u8 then 4_u32
        when 2_u8 then 2_u32
        else           1_u32
        end
      end

      private def sdma_source_from_ports : UInt32
        read_port_u16(0x4A_u8).to_u32 | ((@ports[0x4C] & 0x0F_u8).to_u32 << 16)
      end

      private def sdma_counter_from_ports : UInt32
        read_port_u16(0x4E_u8).to_u32 | ((@ports[0x50] & 0x0F_u8).to_u32 << 16)
      end

      private def write_sdma_ports : Nil
        write_port_u16(0x4A_u8, (@sdma.source & 0xFFFF_u32).to_u16)
        @ports[0x4C] = ((@sdma.source >> 16) & 0x0F_u32).to_u8
        write_port_u16(0x4E_u8, (@sdma.counter & 0xFFFF_u32).to_u16)
        @ports[0x50] = ((@sdma.counter >> 16) & 0x0F_u32).to_u8
      end

      private def write_work_ram(address : UInt32, value : UInt8) : Nil
        return if address > 0x03FFF_u32 && !@model.color?
        @work_ram[address.to_i] = value
      end

      private def gdma_source_blocked?(source : UInt32) : Bool
        (source >= 0x10000_u32 && source <= 0x1FFFF_u32) ||
          (source >= 0x80000_u32 && source <= 0x8FFFF_u32 && (@ports[0xA0] & 0x08_u8) != 0_u8)
      end

      private def write_hypervoice_direct(port : UInt8, value : UInt8) : Nil
        @ports[port] = value
        @ports[0x69] = 0_u8
      end

      private def write_hypervoice_data_latch(value : UInt8) : Nil
        @ports[0x64] = 0_u8
        @ports[0x65] = 0_u8
        @ports[0x66] = 0_u8
        @ports[0x67] = 0_u8
        @ports[0x69] = value
      end

      private def read_save_ram(address : UInt32) : UInt8
        return OPEN_BUS if @save_ram.empty? || !@save_ram_mapped
        @save_ram[bank_index(effective_bank(@ram_bank, @ram_bank_hi), address, @save_ram.size)]
      end

      private def write_save_ram(address : UInt32, value : UInt8) : Nil
        return if @save_ram.empty? || !@save_ram_mapped
        @save_ram[bank_index(effective_bank(@ram_bank, @ram_bank_hi), address, @save_ram.size)] = value
      end

      private def read_rom_bank(bank : UInt8, high : UInt8, address : UInt32) : UInt8
        return OPEN_BUS if @rom.empty?
        @rom[bank_index(effective_bank(bank, high), address, @rom.size)]
      end

      private def read_linear_rom(address : UInt32) : UInt8
        return OPEN_BUS if @rom.empty?
        index = ((@linear_offset.to_u64 << 20) | address.to_u64) % @rom.size.to_u64
        @rom[index.to_i]
      end

      private def bank_index(bank : UInt16, address : UInt32, size : Int) : Int
        (((bank.to_u64 << 16) | (address & 0xFFFF_u32).to_u64) % size.to_u64).to_i
      end

      private def mapper_2003? : Bool
        @cartridge_header.try(&.mapper_2003) || false
      end

      private def effective_bank(low : UInt8, high : UInt8) : UInt16
        return low.to_u16 unless mapper_2003?
        low.to_u16 | (high.to_u16 << 8)
      end

      private def eeprom_address_bits(size : Int) : UInt8
        case size
        when  128 then 6_u8
        when 1024 then 9_u8
        when 2048 then 10_u8
        else           raise ArgumentError.new("unsupported cartridge EEPROM capacity #{size}")
        end
      end

      private def eeprom_control(value : UInt8) : Nil
        eeprom = @eeprom.not_nil!
        data = read_port_u16(0xC4_u8)
        command = read_port_u16(0xC6_u8)
        case value >> 4
        when 1_u8
          eeprom.execute(command)
          write_port_u16(0xC4_u8, eeprom.read_data)
        when 2_u8
          eeprom.write_data(data)
          eeprom.execute(command)
        when 4_u8
          eeprom.execute(command)
        end
        done = case value >> 4
               when 1_u8, 8_u8 then 1_u8
               else                 0_u8
               end
        @ports[0xC8] = (value & 0xF0_u8) | 0x02_u8 | done
      end

      private def read_port_u16(port : UInt8) : UInt16
        @ports[port].to_u16 | (@ports[port &+ 1_u8].to_u16 << 8)
      end

      private def write_counter(port : UInt8, value : UInt16) : Nil
        @ports[port] = (value & 0x00FF_u16).to_u8
        @ports[port &+ 1_u8] = (value >> 8).to_u8
      end

      private def write_port_u16(port : UInt8, value : UInt16) : Nil
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

      private def highest_pending_bit : UInt8
        7.downto(0) do |priority|
          return priority.to_u8 if @ports[0xB4].bit(priority) == 1
        end
        0_u8
      end

      # Mono UART TX-ready is level-triggered: enabling both the UART and
      # IRQ-0 immediately asserts it, ACK cannot clear it while that level is
      # active.  Color/Crystal hardware does not expose this Mono-only level.
      private def refresh_serial_tx_irq : Nil
        if @model == WonderSwanModel::Mono && (@ports[0xB2] & 0x01_u8) != 0_u8 && (@ports[0xB3] & 0x80_u8) != 0_u8
          @ports[0xB4] |= 0x01_u8
        end
      end

      private def color_rendering_enabled? : Bool
        @model.color? && (@ports[0x60] & 0x80_u8) != 0_u8
      end

      private def mono_palette_port_mask(port : UInt8) : UInt8
        case port
        when 0x20_u8..0x27_u8, 0x30_u8..0x37_u8
          0x77_u8
        when 0x28_u8..0x2F_u8, 0x38_u8..0x3F_u8
          (port & 1_u8) == 0_u8 ? 0x70_u8 : 0x77_u8
        else
          0xFF_u8
        end
      end
    end
  end
end
