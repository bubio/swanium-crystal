require "./wonder_swan_sprite_latch"
require "./wonder_swan_palette"

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
      getter current_line : UInt8

      def initialize
        @rgb444 = Array(UInt16).new(PIXEL_COUNT, 0_u16)
        @rgba = Bytes.new(PIXEL_COUNT * 4, 0_u8)
        @sprite_latch = WonderSwanSpriteLatch.new
        @current_line = 0_u8
      end

      # Returns one native RGB444 pixel. The framebuffer remains owned by the
      # PPU so inspection code cannot mutate a rendered frame behind it.
      def pixel_rgb444(x : Int32, y : Int32) : UInt16
        raise IndexError.new("pixel is outside the LCD bounds") unless x.in?(0...SCREEN_WIDTH) && y.in?(0...SCREEN_HEIGHT)
        @rgb444[y * SCREEN_WIDTH + x]
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
        @sprite_latch.reset
      end

      def save_state(io : IO) : Nil
        io.write_byte(@current_line)
        @sprite_latch.save_metadata(io)
        @rgb444.each { |pixel| io.write_bytes(pixel, IO::ByteFormat::LittleEndian) }
        @sprite_latch.save_buffers(io)
      end

      def load_state(io : IO) : Nil
        current_line = read_byte(io)
        unless current_line < SCREEN_HEIGHT
          raise ArgumentError.new("invalid PPU state")
        end

        @current_line = current_line
        @sprite_latch.load_metadata(io)
        @rgb444.map! { io.read_bytes(UInt16, IO::ByteFormat::LittleEndian) }
        @sprite_latch.load_buffers(io)
      end

      def latch_sprites_if_needed(wram : Bytes, ports : Bytes) : Nil
        @sprite_latch.latch_current_if_needed(wram, ports)
      end

      def capture_next_frame_sprites(wram : Bytes, ports : Bytes) : Nil
        @sprite_latch.capture_next(wram, ports)
      end

      def promote_next_frame_sprites : Nil
        @sprite_latch.promote_next
      end

      def render_scanline(line : UInt8, wram : Bytes, ports : Bytes, color_hardware : Bool) : Nil
        y = line.to_i
        return if y >= SCREEN_HEIGHT
        latch_sprites_if_needed(wram, ports) if (ports[0x00] & 0x04) != 0

        color_mode = color_hardware && (ports[0x60] & 0x80) != 0
        display = ports[0x00]
        row = y * SCREEN_WIDTH
        map_mask = color_mode ? 0x0F_u8 : 0x07_u8
        scr1_scroll_x = ports[0x10]
        scr1_bg_y = (line.to_i + ports[0x11].to_i) & 0xFF
        scr1_map_base = (ports[0x07] & 0x0F_u8 & map_mask).to_i << 11
        scr2_scroll_x = ports[0x12]
        scr2_bg_y = (line.to_i + ports[0x13].to_i) & 0xFF
        scr2_map_base = ((ports[0x07] >> 4) & map_mask).to_i << 11
        x = 0
        while x < SCREEN_WIDTH
          color = WonderSwanPalette.backdrop(wram, ports, color_mode)

          if (display & 0x01) != 0
            pixel, palette = background_sample(wram, ports, scr1_scroll_x, scr1_bg_y, scr1_map_base, x, color_mode)
            color = WonderSwanPalette.resolve(wram, ports, palette, pixel, color_mode) unless WonderSwanPalette.transparent?(palette, pixel, color_mode)
          end

          scr2_color = nil.as(UInt16?)
          if (display & 0x02) != 0 && scr2_visible?(ports, display, x, line)
            pixel, palette = background_sample(wram, ports, scr2_scroll_x, scr2_bg_y, scr2_map_base, x, color_mode)
            scr2_color = WonderSwanPalette.resolve(wram, ports, palette, pixel, color_mode) unless WonderSwanPalette.transparent?(palette, pixel, color_mode)
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

      private def background_sample(wram : Bytes, ports : Bytes, scroll_x : UInt8,
                                    bg_y : Int32, map_base : Int32, x : Int32,
                                    color_mode : Bool) : Tuple(UInt8, UInt8)
        bg_x = (x + scroll_x.to_i) & 0xFF
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
        while i < @sprite_latch.current_count && overlaps < 32
          sprite = @sprite_latch.current_at(i)
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
                unless WonderSwanPalette.transparent?(palette, pixel, color_mode)
                  color = WonderSwanPalette.resolve(wram, ports, palette, pixel, color_mode)
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

    end
  end
end
