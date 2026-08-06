require "./ppu"
require "./wonder_swan_bus"

module Swanium
  module Core
    # Copyright-free visual/input fixture used by the SDL demo and image specs.
    module VideoTestPattern
      def self.configure(bus : WonderSwanBus) : Nil
        ram = bus.work_ram
        bus.write_io(0x60_u8, 0xE0_u8) # Color, packed 4bpp
        bus.write_io(0x07_u8, 0x00_u8)
        bus.write_io(0x00_u8, 0x05_u8) # SCR1 + sprites
        bus.write_io(0x04_u8, 0x10_u8) # OAM at 0x2000
        bus.write_io(0x05_u8, 0_u8)
        bus.write_io(0x06_u8, 1_u8)

        # Sixteen vivid RGB444 colors in palette 0.
        colors = StaticArray[
          0x012_u16, 0xF34_u16, 0x2D5_u16, 0x48F_u16,
          0xFD2_u16, 0xF6B_u16, 0x3EE_u16, 0xFFF_u16,
          0x124_u16, 0xA25_u16, 0x184_u16, 0x25A_u16,
          0xC82_u16, 0xB3A_u16, 0x6BB_u16, 0xDDD_u16,
        ]
        colors.each_with_index do |color, index|
          address = 0xFE00 + index * 2
          ram[address] = (color & 0xFF).to_u8
          ram[address + 1] = (color >> 8).to_u8
        end

        # Eight packed 4bpp tiles. Their diagonal/checker structure exercises
        # tile selection and every palette entry without external assets.
        tile = 0
        while tile < 8
          y = 0
          while y < 8
            x = 0
            while x < 8
              pixel = ((tile * 2 + x + y * 3) & 0x0F).to_u8
              address = 0x4000 + tile * 32 + y * 4 + (x >> 1)
              if (x & 1) == 0
                ram[address] = pixel << 4
              else
                ram[address] |= pixel
              end
              x += 1
            end
            y += 1
          end
          tile += 1
        end

        row = 0
        while row < 32
          col = 0
          while col < 32
            word = ((row + col) & 7).to_u16
            word |= 0x4000_u16 if (col & 3) == 3
            word |= 0x8000_u16 if (row & 3) == 3
            address = (row * 32 + col) * 2
            ram[address] = (word & 0xFF).to_u8
            ram[address + 1] = (word >> 8).to_u8
            col += 1
          end
          row += 1
        end

        # A front-priority sprite using tile 7 and palette 8.
        16.times do |index|
          source = 0xFE00 + index * 2
          target = 0xFF00 + index * 2
          ram[target] = ram[source]
          ram[target + 1] = ram[source + 1]
        end
        sprite_word = 7_u16 | 0x2000_u16
        ram[0x2000] = (sprite_word & 0xFF).to_u8
        ram[0x2001] = (sprite_word >> 8).to_u8
        ram[0x2002] = 68_u8
        ram[0x2003] = 108_u8
      end

      def self.render(ppu : Ppu, bus : WonderSwanBus, keys : UInt16 = 0_u16) : Bytes
        bus.set_keys(keys)
        horizontal = 0
        horizontal -= 2 if (keys & WonderSwanKey::X3) != 0
        horizontal += 2 if (keys & WonderSwanKey::X1) != 0
        vertical = 0
        vertical -= 2 if (keys & WonderSwanKey::X4) != 0
        vertical += 2 if (keys & WonderSwanKey::X2) != 0
        bus.write_io(0x10_u8, horizontal.to_u8)
        bus.write_io(0x11_u8, vertical.to_u8)
        ppu.latch_sprites_if_needed(bus.work_ram, bus.ports)
        line = 0
        while line < Ppu::SCREEN_HEIGHT
          ppu.render_scanline(line.to_u8, bus.work_ram, bus.ports, bus.model.color?)
          line += 1
        end
        ppu.framebuffer_rgba
      end
    end
  end
end
