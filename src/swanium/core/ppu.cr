module Swanium
  module Core
    # WonderSwan LCD renderer. The internal framebuffer uses the machine's
    # native RGB444 format; frontends consume the stable RGBA8888 view.
    class Ppu
      SCREEN_WIDTH  = 224
      SCREEN_HEIGHT = 144
      PIXEL_COUNT   = SCREEN_WIDTH * SCREEN_HEIGHT

      TILE_DATA_2BPP = 0x2000
      TILE_DATA_4BPP = 0x4000
      PALETTE_RAM    = 0xFE00

      private struct Sprite
        getter tile : UInt16
        getter palette : UInt8
        getter x : UInt8
        getter y : UInt8
        getter priority : Bool
        getter window : Bool
        getter hflip : Bool
        getter vflip : Bool

        def initialize(@tile = 0_u16, @palette = 0_u8, @x = 0_u8, @y = 0_u8,
                       @priority = false, @window = false, @hflip = false, @vflip = false)
        end
      end

      getter current_line : UInt8

      def initialize
        @rgb444 = Array(UInt16).new(PIXEL_COUNT, 0_u16)
        @rgba = Bytes.new(PIXEL_COUNT * 4, 0_u8)
        @sprites = Array(Sprite).new(128) { Sprite.new }
        @next_sprites = Array(Sprite).new(128) { Sprite.new }
        @sprite_count = 0
        @next_sprite_count = 0
        @sprite_latch_valid = false
        @current_line = 0_u8
      end

      # Native RGB444 pixels, row-major. The returned storage remains owned by
      # the PPU and is valid for the lifetime of this object.
      def framebuffer_rgb444 : Array(UInt16)
        @rgb444
      end

      # Stable frontend API: 224x144 pixels in RGBA8888, row-major, opaque.
      # The same byte buffer is reused on every call.
      def framebuffer_rgba : Bytes
        i = 0
        while i < PIXEL_COUNT
          color = @rgb444[i]
          offset = i * 4
          @rgba[offset] = (((color >> 8) & 0x0F) * 0x11).to_u8
          @rgba[offset + 1] = (((color >> 4) & 0x0F) * 0x11).to_u8
          @rgba[offset + 2] = ((color & 0x0F) * 0x11).to_u8
          @rgba[offset + 3] = 0xFF_u8
          i += 1
        end
        @rgba
      end

      def reset : Nil
        @rgb444.fill(0_u16)
        @rgba.fill(0_u8)
        @current_line = 0_u8
        @sprite_count = 0
        @next_sprite_count = 0
        @sprite_latch_valid = false
      end

      def save_state(io : IO) : Nil
        io.write_byte(@current_line)
        io.write_bytes(@sprite_count.to_u16, IO::ByteFormat::LittleEndian)
        io.write_bytes(@next_sprite_count.to_u16, IO::ByteFormat::LittleEndian)
        io.write_byte(@sprite_latch_valid ? 1_u8 : 0_u8)
        @rgb444.each { |pixel| io.write_bytes(pixel, IO::ByteFormat::LittleEndian) }
        write_sprites(io, @sprites)
        write_sprites(io, @next_sprites)
      end

      def load_state(io : IO) : Nil
        @current_line = read_byte(io)
        @sprite_count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian).to_i
        @next_sprite_count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian).to_i
        @sprite_latch_valid = read_byte(io) != 0_u8
        @rgb444.map! { io.read_bytes(UInt16, IO::ByteFormat::LittleEndian) }
        @sprites = read_sprites(io)
        @next_sprites = read_sprites(io)
      end

      def latch_sprites_if_needed(wram : Bytes, ports : Bytes) : Nil
        latch_sprites(wram, ports, @sprites) unless @sprite_latch_valid
        @sprite_latch_valid = true
      end

      def capture_next_frame_sprites(wram : Bytes, ports : Bytes) : Nil
        @next_sprite_count = latch_sprites(wram, ports, @next_sprites)
      end

      def promote_next_frame_sprites : Nil
        i = 0
        while i < @next_sprite_count
          @sprites[i] = @next_sprites[i]
          i += 1
        end
        @sprite_count = @next_sprite_count
        @sprite_latch_valid = true
      end

      def render_scanline(line : UInt8, wram : Bytes, ports : Bytes, color_hardware : Bool) : Nil
        y = line.to_i
        return if y >= SCREEN_HEIGHT
        latch_sprites_if_needed(wram, ports) if (ports[0x00] & 0x04) != 0

        color_mode = color_hardware && (ports[0x60] & 0x80) != 0
        display = ports[0x00]
        row = y * SCREEN_WIDTH
        x = 0
        while x < SCREEN_WIDTH
          color = backdrop(wram, ports, color_mode)

          if (display & 0x01) != 0
            pixel, palette = background_sample(wram, ports, false, x, line, color_mode)
            color = resolve(wram, ports, palette, pixel, color_mode) unless transparent?(palette, pixel, color_mode)
          end

          scr2_color = nil.as(UInt16?)
          if (display & 0x02) != 0 && scr2_visible?(ports, display, x, line)
            pixel, palette = background_sample(wram, ports, true, x, line, color_mode)
            scr2_color = resolve(wram, ports, palette, pixel, color_mode) unless transparent?(palette, pixel, color_mode)
          end

          if (display & 0x04) != 0
            any, front = sprite_samples(wram, ports, display, x, line, color_mode)
            if scr2_color
              color = front || scr2_color
            else
              color = any || color
            end
          elsif scr2_color
            color = scr2_color
          end

          @rgb444[row + x] = color
          x += 1
        end
        @current_line = line
      end

      private def background_sample(wram : Bytes, ports : Bytes, scr2 : Bool, x : Int32,
                                    line : UInt8, color_mode : Bool) : Tuple(UInt8, UInt8)
        scroll_x = ports[scr2 ? 0x12 : 0x10]
        scroll_y = ports[scr2 ? 0x13 : 0x11]
        bg_x = (x + scroll_x.to_i) & 0xFF
        bg_y = (line.to_i + scroll_y.to_i) & 0xFF
        map_nibble = scr2 ? (ports[0x07] >> 4) : (ports[0x07] & 0x0F)
        map_base = (map_nibble & (color_mode ? 0x0F : 0x07)).to_i << 11
        address = map_base + (((bg_y >> 3) * 32 + (bg_x >> 3)) * 2)
        word = wram[address].to_u16 | (wram[address + 1].to_u16 << 8)
        tile = word & 0x01FF
        tile &+= 512_u16 if color_mode && (word & 0x2000) != 0
        tx = bg_x & 7
        ty = bg_y & 7
        tx = 7 - tx if (word & 0x4000) != 0
        ty = 7 - ty if (word & 0x8000) != 0
        {tile_pixel(wram, ports, tile, tx, ty, color_mode), ((word >> 9) & 0x0F).to_u8}
      end

      private def write_sprites(io : IO, sprites : Array(Sprite)) : Nil
        sprites.each do |sprite|
          io.write_bytes(sprite.tile, IO::ByteFormat::LittleEndian)
          io.write_byte(sprite.palette)
          io.write_byte(sprite.x)
          io.write_byte(sprite.y)
          flags = 0_u8
          flags |= 0x01_u8 if sprite.priority
          flags |= 0x02_u8 if sprite.window
          flags |= 0x04_u8 if sprite.hflip
          flags |= 0x08_u8 if sprite.vflip
          io.write_byte(flags)
        end
      end

      private def read_sprites(io : IO) : Array(Sprite)
        Array(Sprite).new(128) do
          tile = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
          palette = read_byte(io)
          x = read_byte(io)
          y = read_byte(io)
          flags = read_byte(io)
          Sprite.new(tile, palette, x, y,
            (flags & 0x01_u8) != 0_u8, (flags & 0x02_u8) != 0_u8,
            (flags & 0x04_u8) != 0_u8, (flags & 0x08_u8) != 0_u8)
        end
      end

      private def read_byte(io : IO) : UInt8
        io.read_byte || raise IO::EOFError.new
      end

      private def tile_pixel(wram : Bytes, ports : Bytes, tile : UInt16, tx : Int32,
                             ty : Int32, color_mode : Bool) : UInt8
        four_bpp = color_mode && (ports[0x60] & 0x40) != 0
        if four_bpp
          address = TILE_DATA_4BPP + tile.to_i * 32 + ty * 4
          if (ports[0x60] & 0x20) != 0
            byte = wram[address + (tx >> 1)]
            return (tx & 1) == 0 ? (byte >> 4) : (byte & 0x0F)
          end
          bit = 7 - tx
          pixel = 0_u8
          plane = 0
          while plane < 4
            pixel |= (((wram[address + plane] >> bit) & 1) << plane).to_u8
            plane += 1
          end
          pixel
        else
          address = TILE_DATA_2BPP + tile.to_i * 16 + ty * 2
          bit = 7 - tx
          ((wram[address] >> bit) & 1) | (((wram[address + 1] >> bit) & 1) << 1)
        end
      end

      private def sprite_samples(wram : Bytes, ports : Bytes, display : UInt8, x : Int32,
                                 line : UInt8, color_mode : Bool) : Tuple(UInt16?, UInt16?)
        any = nil.as(UInt16?)
        front = nil.as(UInt16?)
        overlaps = 0
        i = 0
        while i < @sprite_count && overlaps < 32
          sprite = @sprites[i]
          dy = line &- sprite.y
          if dy < 8
            overlaps += 1
            dx = x.to_u8 &- sprite.x
            if dx < 8
              hidden = (display & 0x08) != 0 && sprite.window &&
                       in_window?(ports, x, line, 0x0C)
              unless hidden
                tx = sprite.hflip ? 7 - dx.to_i : dx.to_i
                ty = sprite.vflip ? 7 - dy.to_i : dy.to_i
                pixel = tile_pixel(wram, ports, sprite.tile, tx, ty, color_mode)
                palette = sprite.palette &+ 8_u8
                unless transparent?(palette, pixel, color_mode)
                  color = resolve(wram, ports, palette, pixel, color_mode)
                  any ||= color
                  front ||= color if sprite.priority
                end
              end
            end
          end
          i += 1
        end
        {any, front}
      end

      private def scr2_visible?(ports : Bytes, display : UInt8, x : Int32, line : UInt8) : Bool
        return true if (display & 0x20) == 0
        inside = in_window?(ports, x, line, 0x08)
        (display & 0x10) != 0 ? !inside : inside
      end

      private def in_window?(ports : Bytes, x : Int32, y : UInt8, base : Int32) : Bool
        x.to_u8 >= ports[base] && x.to_u8 <= ports[base + 2] &&
          y >= ports[base + 1] && y <= ports[base + 3]
      end

      private def resolve(wram : Bytes, ports : Bytes, palette : UInt8, pixel : UInt8,
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

      private def transparent?(palette : UInt8, pixel : UInt8, color_mode : Bool) : Bool
        return false unless pixel == 0
        return true if color_mode
        p = palette & 0x0F
        !((p <= 3) || (p >= 8 && p <= 11))
      end

      private def backdrop(wram : Bytes, ports : Bytes, color_mode : Bool) : UInt16
        if color_mode
          index = ports[0x01].to_i * 2 + PALETTE_RAM
          (wram[index].to_u16 | (wram[index + 1].to_u16 << 8)) & 0x0FFF
        else
          grey(shade_from_pool(ports, ports[0x01] & 0x07))
        end
      end

      private def shade_from_pool(ports : Bytes, index : UInt8) : UInt8
        byte = ports[0x1C + (index >> 1).to_i]
        (index & 1) == 0 ? (byte & 0x0F) : ((byte >> 4) & 0x0F)
      end

      private def grey(shade : UInt8) : UInt16
        value = (15_u16 - (shade & 0x0F).to_u16)
        (value << 8) | (value << 4) | value
      end

      private def latch_sprites(wram : Bytes, ports : Bytes, target : Array(Sprite)) : Int32
        base = (ports[0x04] & 0x3F).to_i << 9
        first = ports[0x05].to_i
        count = Math.min(ports[0x06].to_i, 128)
        i = 0
        while i < count
          index = (first + i) & 127
          address = base + index * 4
          word = wram[address].to_u16 | (wram[address + 1].to_u16 << 8)
          target[i] = Sprite.new(
            tile: word & 0x01FF,
            palette: ((word >> 9) & 0x07).to_u8,
            x: wram[address + 3],
            y: wram[address + 2],
            priority: (word & 0x2000) != 0,
            window: (word & 0x1000) != 0,
            hflip: (word & 0x4000) != 0,
            vflip: (word & 0x8000) != 0
          )
          i += 1
        end
        @sprite_count = count if target.same?(@sprites)
        count
      end
    end
  end
end
