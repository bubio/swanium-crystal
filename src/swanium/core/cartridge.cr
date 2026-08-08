module Swanium
  module Core
    # Cartridge metadata lives in the final sixteen bytes of a WonderSwan ROM.
    # Parsing is deliberately independent of file I/O so it is usable from the
    # GUI, command line, and headless tests alike.
    enum SaveMedium
      None
      Sram8KiB
      Sram32KiB
      Sram128KiB
      Sram256KiB
      Sram512KiB
      Eeprom128B
      Eeprom1KiB
      Eeprom2KiB

      def size : Int32
        case self
        when Sram8KiB   then 8 * 1024
        when Sram32KiB  then 32 * 1024
        when Sram128KiB then 128 * 1024
        when Sram256KiB then 256 * 1024
        when Sram512KiB then 512 * 1024
        when Eeprom128B then 128
        when Eeprom1KiB then 1024
        when Eeprom2KiB then 2 * 1024
        else                 0
        end
      end

      def sram? : Bool
        self.in?(Sram8KiB, Sram32KiB, Sram128KiB, Sram256KiB, Sram512KiB)
      end
    end

    struct CartridgeHeader
      FOOTER_SIZE = 16

      getter color_required : Bool
      getter save_medium : SaveMedium
      getter vertical : Bool
      getter mapper_2003 : Bool
      getter rtc : Bool
      getter game_id : UInt8
      getter version : UInt8

      def initialize(@color_required : Bool, @save_medium : SaveMedium, @vertical : Bool,
                     @mapper_2003 : Bool, @rtc : Bool, @game_id : UInt8, @version : UInt8)
      end

      def self.parse(rom : Bytes) : CartridgeHeader
        raise ArgumentError.new("ROM is shorter than the 16-byte WonderSwan cartridge footer") if rom.size < FOOTER_SIZE
        footer = rom.size - FOOTER_SIZE
        raise ArgumentError.new("ROM has no WonderSwan far-jump boot entry") unless rom[footer] == 0xEA_u8

        new(
          (rom[footer + 7] & 0x01_u8) != 0_u8,
          save_medium_from(rom[footer + 11]),
          (rom[footer + 12] & 0x01_u8) != 0_u8,
          rom[footer + 13] == 1_u8,
          (rom[footer + 12] & 0x04_u8) != 0_u8 && rom[footer + 13] != 0_u8,
          rom[footer + 8],
          rom[footer + 9]
        )
      end

      private def self.save_medium_from(code : UInt8) : SaveMedium
        case code
        when 0x01_u8 then SaveMedium::Sram8KiB
        when 0x02_u8 then SaveMedium::Sram32KiB
        when 0x03_u8 then SaveMedium::Sram128KiB
        when 0x04_u8 then SaveMedium::Sram256KiB
        when 0x05_u8 then SaveMedium::Sram512KiB
        when 0x10_u8 then SaveMedium::Eeprom128B
        when 0x20_u8 then SaveMedium::Eeprom2KiB
        when 0x50_u8 then SaveMedium::Eeprom1KiB
        else              SaveMedium::None
        end
      end
    end

    struct CartridgeImage
      @rom : Bytes

      getter header : CartridgeHeader

      def initialize(rom : Bytes, @header : CartridgeHeader)
        @rom = rom.dup
      end

      def self.from_bytes(rom : Bytes) : CartridgeImage
        raise ArgumentError.new("ROM is empty") if rom.empty?
        raise ArgumentError.new("ROM is larger than 16 MiB") if rom.size > 16 * 1024 * 1024
        new(rom, CartridgeHeader.parse(rom))
      end

      # ROM contents are immutable cartridge input. Return a copy so callers
      # cannot alter the image after its footer and mapper have been accepted.
      def rom_snapshot : Bytes
        @rom.dup
      end

      def model : WonderSwanModel
        @header.color_required ? WonderSwanModel::Color : WonderSwanModel::Mono
      end
    end

    # 93Cxx-style cartridge EEPROM. The backing bytes are owned by the bus so
    # frontend persistence and save states can use the same raw save medium as
    # SRAM without knowing the cartridge's electrical interface.
    class CartridgeEeprom
      def initialize(@contents : Bytes, @address_bits : UInt8)
        @input = 0_u16
        @output = 0xFFFF_u16
        @write_enabled = false
      end

      def read_data : UInt16
        @output
      end

      def write_data(value : UInt16) : Nil
        @input = value
      end

      def execute(command : UInt16) : Nil
        return if command >> (@address_bits + 3) != 0_u16
        return if ((command >> (@address_bits + 2)) & 1_u16) == 0_u16
        opcode = (command >> @address_bits) & 3_u16
        if opcode == 0_u16
          execute_extended((command >> (@address_bits - 2)) & 3_u16)
          return
        end
        byte_address = ((command & ((1_u16 << @address_bits) - 1_u16)) * 2_u16).to_i
        return if byte_address + 1 >= @contents.size
        case opcode
        when 1_u16
          return unless @write_enabled
          @contents[byte_address] = (@input & 0xFF_u16).to_u8
          @contents[byte_address + 1] = (@input >> 8).to_u8
        when 2_u16
          @output = @contents[byte_address].to_u16 | (@contents[byte_address + 1].to_u16 << 8)
        when 3_u16
          return unless @write_enabled
          @contents[byte_address] = 0xFF_u8
          @contents[byte_address + 1] = 0xFF_u8
        end
      end

      private def execute_extended(operation : UInt16) : Nil
        case operation
        when 0_u16 then @write_enabled = false
        when 3_u16 then @write_enabled = true
        when 1_u16
          return unless @write_enabled
          @contents.each_index do |index|
            @contents[index] = index.even? ? (@input & 0xFF_u16).to_u8 : (@input >> 8).to_u8
          end
        when 2_u16
          @contents.fill(0xFF_u8) if @write_enabled
        end
      end
    end
  end
end
