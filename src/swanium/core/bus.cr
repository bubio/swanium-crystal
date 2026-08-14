require "./memory_bus"
require "./apu"
require "./cartridge"
require "./rtc"
require "./dma_controller"
require "./hardware"
require "./interrupt_controller"

module Swanium
  module Core
    # Platform-neutral first hardware bus. It models the CPU-visible address
    # map and cartridge bank registers while PPU/APU/DMA devices are added on
    # top through the same I/O port file.
    class WonderSwanBus < MemoryBus
      OPEN_BUS = 0xFF_u8
      @rom : Bytes

      getter model : WonderSwanModel
      getter linear_offset : UInt8
      getter ram_bank : UInt8
      getter ram_bank_hi : UInt8
      getter rom_bank0 : UInt8
      getter rom_bank0_hi : UInt8
      getter rom_bank1 : UInt8
      getter rom_bank1_hi : UInt8
      getter cartridge_header : CartridgeHeader?

      def initialize(rom : Bytes = Bytes.new(0), save_ram_size : Int = 0, @model : WonderSwanModel = WonderSwanModel::Mono,
                     @cartridge_header : CartridgeHeader? = nil, @save_ram_mapped : Bool = true)
        raise ArgumentError.new("save RAM size must not be negative") if save_ram_size < 0
        @rom = rom.dup
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
        @interrupts = WonderSwanInterruptController.new(@ports, @model)
        @voice_writes = [] of UInt8
        @dma = WonderSwanDmaController.new(@ports, @model)
        @ports[0x9E] = 0x03_u8
      end

      def self.from_cartridge(cartridge : CartridgeImage) : WonderSwanBus
        header = cartridge.header
        # This product intentionally emulates SwanCrystal for every cartridge.
        # The footer's color-required bit describes the minimum console, not
        # the selected host hardware; Mono and Color cartridges run through
        # SwanCrystal's backwards-compatible hardware path.
        new(cartridge.rom_snapshot, save_ram_size: header.save_medium.size, model: WonderSwanModel::Crystal,
          cartridge_header: header, save_ram_mapped: header.save_medium.sram?)
      end

      def replace_save_ram(data : Bytes) : Nil
        raise ArgumentError.new("save data size does not match cartridge") unless data.size == @save_ram.size
        @save_ram.copy_from(data)
      end

      # Snapshot methods intentionally return independent buffers. Hardware
      # state must otherwise be mutated through the address or I/O maps so
      # device-specific masks and side effects cannot be bypassed.
      def work_ram_snapshot : Bytes
        @work_ram.dup
      end

      def save_ram_snapshot : Bytes
        @save_ram.dup
      end

      def ports_snapshot : Bytes
        @ports.dup
      end

      def work_ram_size : Int32
        @work_ram.size
      end

      def save_ram_size : Int32
        @save_ram.size
      end

      def ports_size : Int32
        @ports.size
      end

      def has_save_ram? : Bool
        !@save_ram.empty?
      end

      # PPU access stays behind the bus boundary: the renderer receives the
      # internal views it requires, while frontends never receive mutable RAM
      # or port-file references.
      def latch_sprites(ppu : Ppu) : Nil
        ppu.latch_sprites_if_needed(@work_ram, @ports)
      end

      def capture_next_frame_sprites(ppu : Ppu) : Nil
        ppu.capture_next_frame_sprites(@work_ram, @ports)
      end

      def render_scanline(ppu : Ppu, line : UInt8) : Nil
        ppu.render_scanline(line, @work_ram, @ports, @model.color?)
      end

      def interrupt_pending?(source : WonderSwanInterrupt) : Bool
        (@ports[0xB4] & (1_u8 << source.value)) != 0_u8
      end

      # Drains the voice writes collected during the preceding CPU instruction.
      # This runs at every instruction boundary, so retain the backing storage
      # instead of replacing it with a newly allocated Array each time.
      def consume_voice_writes(&) : Nil
        @voice_writes.each { |sample| yield sample }
        @voice_writes.clear
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
        @dma.tick_sound(cycles, apu, @work_ram, color_rendering_enabled?, self)
      end

      def save_dma_state(io : IO) : Nil
        @dma.save_state(io)
      end

      def load_dma_state(io : IO) : Nil
        @dma.load_state(io)
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
        if value = @interrupts.read_io?(port)
          return value
        end

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
        else                                         @ports[port]
        end
      end

      def write_io(port : UInt8, value : UInt8) : Nil
        return if @interrupts.write_io?(port, value)

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
          request_interrupt(WonderSwanInterrupt::DmaComplete) if color_rendering_enabled? && @dma.write_io(port, value, self)
        when 0xA4_u8, 0xA5_u8, 0xA6_u8, 0xA7_u8
          @ports[port] = value
          @ports[port &+ 4_u8] = value
        when 0xA8_u8..0xAB_u8, 0xAD_u8..0xAF_u8, 0xB1_u8
          # Hardware-maintained counters and INT_CAUSE are read-only.
        else
          @ports[port] = value
        end
      end

      def consume_wait_cycles : UInt32
        @dma.consume_wait_cycles
      end

      def request_interrupt(source : WonderSwanInterrupt) : Nil
        @interrupts.request(source)
      end

      # The platform layer supplies a complete input snapshot. Only a newly
      # pressed key raises the edge-triggered KeyPress source.
      def set_keys(keys : UInt16) : Nil
        @interrupts.set_keys(keys)
      end

      def keys : UInt16
        @interrupts.keys
      end

      def pending_interrupt_vector? : UInt8?
        @interrupts.pending_vector?
      end

      # Called by the LCD scheduler at the beginning of HBlank.
      def on_hblank : Nil
        @interrupts.on_hblank
      end

      # Called by the LCD scheduler on the VBlank transition.
      def on_vblank : Nil
        @interrupts.on_vblank
      end

      # The display controller updates this once per 256-cycle scanline.
      def set_current_scanline(line : UInt8) : Nil
        @interrupts.set_current_scanline(line)
      end

      def restore_state(work_ram : Bytes, save_ram : Bytes, ports : Bytes, keys : UInt16,
                        linear_offset : UInt8, ram_bank : UInt8, ram_bank_hi : UInt8,
                        rom_bank0 : UInt8, rom_bank0_hi : UInt8, rom_bank1 : UInt8, rom_bank1_hi : UInt8) : Nil
        raise ArgumentError.new("state RAM size does not match machine") unless work_ram.size == @work_ram.size && save_ram.size == @save_ram.size
        raise ArgumentError.new("state port file has invalid size") unless ports.size == @ports.size
        @work_ram.copy_from(work_ram)
        @save_ram.copy_from(save_ram)
        @ports.copy_from(ports)
        @interrupts.restore_keys(keys)
        @linear_offset = linear_offset
        @ram_bank = ram_bank
        @ram_bank_hi = ram_bank_hi
        @rom_bank0 = rom_bank0
        @rom_bank0_hi = rom_bank0_hi
        @rom_bank1 = rom_bank1
        @rom_bank1_hi = rom_bank1_hi
        @dma.reset
      end

      private def read_work_ram(address : UInt32) : UInt8
        return OPEN_BUS if address > 0x03FFF_u32 && !@model.color?
        @work_ram[address.to_i]
      end

      private def write_work_ram(address : UInt32, value : UInt8) : Nil
        return if address > 0x03FFF_u32 && !@model.color?
        @work_ram[address.to_i] = value
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

      private def write_port_u16(port : UInt8, value : UInt16) : Nil
        @ports[port] = (value & 0x00FF_u16).to_u8
        @ports[port &+ 1_u8] = (value >> 8).to_u8
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
