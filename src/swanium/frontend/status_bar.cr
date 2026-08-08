module Swanium
  module Frontend
    # A compact SDL-rendered counterpart to Swanium's bottom status bar. It is
    # kept separate from the emulated framebuffer so overlays never obscure UI.
    module StatusBar
      HEIGHT      =           22
      private BAR_COLOR   = 0x1E1E1E_u32
      private TEXT_COLOR  = 0xCCCCCC_u32
      private TRACK_COLOR = 0x505050_u32
      private FILL_COLOR  = 0xA8A8A8_u32

      def self.render(destination : Bytes, frame : Bytes, width : Int32, height : Int32,
                      label : String, fps : Float64, paused : Bool, volume : Int32) : Nil
        raise ArgumentError.new("status bar destination has the wrong size") unless destination.size == width * (height + HEIGHT) * 4
        raise ArgumentError.new("status bar frame has the wrong size") unless frame.size == width * height * 4

        destination[0, frame.size].copy_from(frame)
        fill_rect(destination, width, height, 0, 0, width, HEIGHT, BAR_COLOR)

        status = paused ? "#{label} - PAUSED" : "#{label} - #{fps.round.to_i} FPS"
        slider_width = width >= 220 ? 70 : 0
        text_right = slider_width > 0 ? width - slider_width - 31 : width - 8
        draw_text(destination, width, height, 8, 8, status, TEXT_COLOR, text_right)
        return if slider_width == 0

        speaker_x = width - slider_width - 27
        draw_speaker(destination, width, height, speaker_x, 7)
        draw_slider(destination, width, height, speaker_x + 18, volume.clamp(0, 100), slider_width)
      end

      private def self.draw_slider(rgba : Bytes, width : Int32, origin_y : Int32, x : Int32, volume : Int32, slider_width : Int32) : Nil
        y = origin_y + 10
        fill_rect(rgba, width, origin_y, x, y, slider_width, 3, TRACK_COLOR)
        filled = (slider_width - 2) * volume // 100
        fill_rect(rgba, width, origin_y, x, y, filled + 1, 3, FILL_COLOR)
        knob_x = x + filled
        fill_rect(rgba, width, origin_y, knob_x, y - 3, 3, 9, TEXT_COLOR)
      end

      private def self.draw_speaker(rgba : Bytes, width : Int32, origin_y : Int32, x : Int32, y : Int32) : Nil
        fill_rect(rgba, width, origin_y, x, y + 3, 3, 6, TEXT_COLOR)
        fill_rect(rgba, width, origin_y, x + 3, y + 1, 2, 10, TEXT_COLOR)
        put_pixel(rgba, width, origin_y, x + 6, y + 2, TEXT_COLOR)
        put_pixel(rgba, width, origin_y, x + 7, y + 3, TEXT_COLOR)
        put_pixel(rgba, width, origin_y, x + 8, y + 5, TEXT_COLOR)
        put_pixel(rgba, width, origin_y, x + 7, y + 7, TEXT_COLOR)
        put_pixel(rgba, width, origin_y, x + 6, y + 8, TEXT_COLOR)
      end

      private def self.fill_rect(rgba : Bytes, width : Int32, origin_y : Int32, x : Int32, y : Int32,
                                 rect_width : Int32, rect_height : Int32, color : UInt32) : Nil
        rect_height.times do |dy|
          rect_width.times { |dx| put_pixel(rgba, width, origin_y, x + dx, y + dy, color) }
        end
      end

      private def self.draw_text(rgba : Bytes, width : Int32, origin_y : Int32, x : Int32, y : Int32,
                                 text : String, color : UInt32, right : Int32) : Nil
        cursor = x
        text.upcase.each_char do |char|
          break if cursor + 5 > right
          bits = glyph(char)
          7.times do |row|
            5.times do |column|
              put_pixel(rgba, width, origin_y, cursor + column, y + row, color) if (bits & (1_u64 << (row * 5 + column))) != 0
            end
          end
          cursor += 6
        end
      end

      private def self.put_pixel(rgba : Bytes, width : Int32, origin_y : Int32, x : Int32, y : Int32, color : UInt32) : Nil
        return unless x >= 0 && x < width && y >= 0 && y < HEIGHT
        offset = ((origin_y + y) * width + x) * 4
        rgba[offset] = ((color >> 16) & 0xFF_u32).to_u8
        rgba[offset + 1] = ((color >> 8) & 0xFF_u32).to_u8
        rgba[offset + 2] = (color & 0xFF_u32).to_u8
        rgba[offset + 3] = 0xFF_u8
      end

      # Five-by-seven font for the small, fixed-size status UI.
      private def self.glyph(char : Char) : UInt64
        rows = case char
               when 'A' then {"01110", "10001", "10001", "11111", "10001", "10001", "10001"}
               when 'B' then {"11110", "10001", "10001", "11110", "10001", "10001", "11110"}
               when 'C' then {"01111", "10000", "10000", "10000", "10000", "10000", "01111"}
               when 'D' then {"11110", "10001", "10001", "10001", "10001", "10001", "11110"}
               when 'E' then {"11111", "10000", "10000", "11110", "10000", "10000", "11111"}
               when 'F' then {"11111", "10000", "10000", "11110", "10000", "10000", "10000"}
               when 'G' then {"01111", "10000", "10000", "10111", "10001", "10001", "01111"}
               when 'H' then {"10001", "10001", "10001", "11111", "10001", "10001", "10001"}
               when 'I' then {"11111", "00100", "00100", "00100", "00100", "00100", "11111"}
               when 'J' then {"00111", "00010", "00010", "00010", "10010", "10010", "01100"}
               when 'K' then {"10001", "10010", "10100", "11000", "10100", "10010", "10001"}
               when 'L' then {"10000", "10000", "10000", "10000", "10000", "10000", "11111"}
               when 'M' then {"10001", "11011", "10101", "10101", "10001", "10001", "10001"}
               when 'N' then {"10001", "11001", "10101", "10011", "10001", "10001", "10001"}
               when 'O' then {"01110", "10001", "10001", "10001", "10001", "10001", "01110"}
               when 'P' then {"11110", "10001", "10001", "11110", "10000", "10000", "10000"}
               when 'Q' then {"01110", "10001", "10001", "10001", "10101", "10010", "01101"}
               when 'R' then {"11110", "10001", "10001", "11110", "10100", "10010", "10001"}
               when 'S' then {"01111", "10000", "10000", "01110", "00001", "00001", "11110"}
               when 'T' then {"11111", "00100", "00100", "00100", "00100", "00100", "00100"}
               when 'U' then {"10001", "10001", "10001", "10001", "10001", "10001", "01110"}
               when 'V' then {"10001", "10001", "10001", "10001", "10001", "01010", "00100"}
               when 'W' then {"10001", "10001", "10001", "10101", "10101", "10101", "01010"}
               when 'X' then {"10001", "10001", "01010", "00100", "01010", "10001", "10001"}
               when 'Y' then {"10001", "10001", "01010", "00100", "00100", "00100", "00100"}
               when 'Z' then {"11111", "00001", "00010", "00100", "01000", "10000", "11111"}
               when '0' then {"01110", "10001", "10011", "10101", "11001", "10001", "01110"}
               when '1' then {"00100", "01100", "00100", "00100", "00100", "00100", "01110"}
               when '2' then {"01110", "10001", "00001", "00010", "00100", "01000", "11111"}
               when '3' then {"11110", "00001", "00001", "01110", "00001", "00001", "11110"}
               when '4' then {"00010", "00110", "01010", "10010", "11111", "00010", "00010"}
               when '5' then {"11111", "10000", "10000", "11110", "00001", "00001", "11110"}
               when '6' then {"01110", "10000", "10000", "11110", "10001", "10001", "01110"}
               when '7' then {"11111", "00001", "00010", "00100", "01000", "01000", "01000"}
               when '8' then {"01110", "10001", "10001", "01110", "10001", "10001", "01110"}
               when '9' then {"01110", "10001", "10001", "01111", "00001", "00001", "01110"}
               when '-' then {"00000", "00000", "00000", "11111", "00000", "00000", "00000"}
               when '.' then {"00000", "00000", "00000", "00000", "00000", "00110", "00110"}
               else          {"00000", "00000", "00000", "00000", "00000", "00000", "00000"}
               end
        bits = 0_u64
        rows.each_with_index do |row, y|
          row.each_char_with_index { |pixel, x| bits |= 1_u64 << (y * 5 + x) if pixel == '1' }
        end
        bits
      end
    end
  end
end
