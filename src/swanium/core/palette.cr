module Swanium
  module Core
    # Stateless WonderSwan palette RAM and monochrome shade resolver.
    module WonderSwanPalette
      PALETTE_RAM = 0xFE00

      def self.resolve(wram : Bytes, ports : Bytes, palette : UInt8, pixel : UInt8,
                       color_mode : Bool) : UInt16
        if color_mode
          entry = ((palette & 0x0F).to_i * 16 + (pixel & 0x0F).to_i) * 2 + PALETTE_RAM
          return (wram[entry].to_u16 | (wram[entry + 1].to_u16 << 8)) & 0x0FFF
        end
        address = 0x20 + (palette & 0x0F).to_i * 2 + (pixel >> 1).to_i
        byte = ports[address]
        pool = (pixel & 1) == 0 ? (byte & 0x07) : ((byte >> 4) & 0x07)
        grey(shade_from_pool(ports, pool))
      end

      def self.transparent?(palette : UInt8, pixel : UInt8, color_mode : Bool) : Bool
        return false unless pixel == 0_u8
        return true if color_mode
        p = palette & 0x0F_u8
        !((p <= 3_u8) || (p >= 8_u8 && p <= 11_u8))
      end

      def self.backdrop(wram : Bytes, ports : Bytes, color_mode : Bool) : UInt16
        if color_mode
          index = ports[0x01].to_i * 2 + PALETTE_RAM
          (wram[index].to_u16 | (wram[index + 1].to_u16 << 8)) & 0x0FFF
        else
          grey(shade_from_pool(ports, ports[0x01] & 0x07_u8))
        end
      end

      private def self.shade_from_pool(ports : Bytes, index : UInt8) : UInt8
        byte = ports[0x1C + (index >> 1).to_i]
        (index & 1_u8) == 0_u8 ? (byte & 0x0F_u8) : ((byte >> 4) & 0x0F_u8)
      end

      private def self.grey(shade : UInt8) : UInt16
        value = 15_u16 - (shade & 0x0F_u8).to_u16
        (value << 8) | (value << 4) | value
      end
    end
  end
end
