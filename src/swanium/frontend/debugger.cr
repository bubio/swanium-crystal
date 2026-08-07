require "../core/machine"

module Swanium
  module Frontend
    # Keyboard-driven debugger state and a tiny allocation-light RGBA overlay.
    class Debugger
      getter paused : Bool
      getter visible : Bool
      getter memory_address : UInt32

      def initialize
        @paused = false
        @visible = false
        @step_requested = false
        @memory_address = 0_u32
        @trace = Array(Core::InstructionTrace).new(8)
        @saved_display_control = nil.as(UInt8?)
      end

      def toggle_visible : Nil
        @visible = !@visible
      end

      def toggle_pause : Nil
        @paused = !@paused
      end

      def request_step : Nil
        @paused = true
        @step_requested = true
      end

      def run_instruction?(machine : Core::Machine, bus : Core::WonderSwanBus) : Bool
        return false if @paused && !@step_requested
        @step_requested = false
        machine.step_wonder_swan(bus)
        if trace = machine.cpu.last_trace
          @trace.shift if @trace.size == 8
          @trace << trace
        end
        true
      end

      def move_memory(delta : Int32) : Nil
        @memory_address = (@memory_address.to_i64 + delta).clamp(0_i64, 0xFFFFF_i64).to_u32
      end

      # Layer 0/1/2 correspond to SCR1, SCR2 and sprites.
      def toggle_layer(bus : Core::WonderSwanBus, layer : Int32) : Nil
        bit = 1_u8 << layer
        control = bus.ports[0x00]
        @saved_display_control ||= control
        bus.write_io(0x00_u8, control ^ bit)
      end

      def render(rgba : Bytes, machine : Core::Machine, bus : Core::WonderSwanBus,
                 audio_latency_ms : UInt32 = 0_u32, audio_underruns : UInt32 = 0_u32) : Nil
        return unless @visible
        fill_rect(rgba, 2, 2, 220, 54, 0x101018_u32)
        registers = machine.cpu.registers
        draw_text(rgba, 5, 5, @paused ? "PAUSED" : "RUN", 0xFFFF55_u32)
        draw_text(rgba, 53, 5, "#{registers.cs.to_s(16).upcase.rjust(4, '0')}:#{registers.ip.to_s(16).upcase.rjust(4, '0')}", 0xFFFFFF_u32)
        draw_text(rgba, 5, 14, "AX #{hex4(registers.ax)} BX #{hex4(registers.bx)} SP #{hex4(registers.sp)}", 0x77FFFF_u32)
        draw_text(rgba, 5, 23, "MEM #{hex5(@memory_address)} #{memory_row(bus)}", 0xFFAA77_u32)
        if trace = @trace.last?
          draw_text(rgba, 5, 32, "TRACE #{hex4(trace.code_segment)}:#{hex4(trace.instruction_pointer)} OP #{hex2(trace.opcode)} C #{trace.cycles}", 0xAAFFAA_u32)
        end
        layers = bus.ports[0x00]
        draw_text(rgba, 5, 41, "LAYERS 1#{on_off(layers, 0)} 2#{on_off(layers, 1)} 3#{on_off(layers, 2)}", 0xCCCCFF_u32)
        draw_text(rgba, 5, 50, "AUDIO #{audio_latency_ms}MS DROP #{audio_underruns}", 0xFFCC88_u32)
      end

      private def memory_row(bus : Core::WonderSwanBus) : String
        String.build do |text|
          8.times do |index|
            text << ' ' unless index == 0
            text << hex2(bus.read_u8((@memory_address + index) & 0xFFFFF_u32))
          end
        end
      end

      private def on_off(value : UInt8, bit : Int32) : String
        value.bit(bit) == 1 ? "+" : "-"
      end

      private def hex2(value : UInt8) : String
        value.to_s(16).upcase.rjust(2, '0')
      end

      private def hex4(value : UInt16) : String
        value.to_s(16).upcase.rjust(4, '0')
      end

      private def hex5(value : UInt32) : String
        value.to_s(16).upcase.rjust(5, '0')
      end

      private def fill_rect(rgba : Bytes, x : Int32, y : Int32, width : Int32, height : Int32, color : UInt32) : Nil
        height.times do |dy|
          width.times { |dx| put_pixel(rgba, x + dx, y + dy, color) }
        end
      end

      private def draw_text(rgba : Bytes, x : Int32, y : Int32, text : String, color : UInt32) : Nil
        cursor = x
        text.each_char do |char|
          bits = glyph(char)
          7.times do |row|
            5.times do |column|
              put_pixel(rgba, cursor + column, y + row, color) if (bits & (1_u64 << (row * 5 + column))) != 0
            end
          end
          cursor += 6
        end
      end

      private def put_pixel(rgba : Bytes, x : Int32, y : Int32, color : UInt32) : Nil
        return unless x >= 0 && x < Core::Ppu::SCREEN_WIDTH && y >= 0 && y < Core::Ppu::SCREEN_HEIGHT
        offset = (y * Core::Ppu::SCREEN_WIDTH + x) * 4
        rgba[offset] = ((color >> 16) & 0xFF_u32).to_u8
        rgba[offset + 1] = ((color >> 8) & 0xFF_u32).to_u8
        rgba[offset + 2] = (color & 0xFF_u32).to_u8
        rgba[offset + 3] = 0xFF_u8
      end

      # Five by seven uppercase diagnostic font, packed row-major.
      private def glyph(char : Char) : UInt64
        rows = case char
               when 'A' then {"01110", "10001", "10001", "11111", "10001", "10001", "10001"}
               when 'B' then {"11110", "10001", "10001", "11110", "10001", "10001", "11110"}
               when 'C' then {"01111", "10000", "10000", "10000", "10000", "10000", "01111"}
               when 'D' then {"11110", "10001", "10001", "10001", "10001", "10001", "11110"}
               when 'E' then {"11111", "10000", "10000", "11110", "10000", "10000", "11111"}
               when 'F' then {"11111", "10000", "10000", "11110", "10000", "10000", "10000"}
               when 'I' then {"11111", "00100", "00100", "00100", "00100", "00100", "11111"}
               when 'L' then {"10000", "10000", "10000", "10000", "10000", "10000", "11111"}
               when 'M' then {"10001", "11011", "10101", "10101", "10001", "10001", "10001"}
               when 'N' then {"10001", "11001", "10101", "10011", "10001", "10001", "10001"}
               when 'O' then {"01110", "10001", "10001", "10001", "10001", "10001", "01110"}
               when 'P' then {"11110", "10001", "10001", "11110", "10000", "10000", "10000"}
               when 'R' then {"11110", "10001", "10001", "11110", "10100", "10010", "10001"}
               when 'S' then {"01111", "10000", "10000", "01110", "00001", "00001", "11110"}
               when 'T' then {"11111", "00100", "00100", "00100", "00100", "00100", "00100"}
               when 'U' then {"10001", "10001", "10001", "10001", "10001", "10001", "01110"}
               when 'V' then {"10001", "10001", "10001", "10001", "10001", "01010", "00100"}
               when 'X' then {"10001", "10001", "01010", "00100", "01010", "10001", "10001"}
               when 'Y' then {"10001", "10001", "01010", "00100", "00100", "00100", "00100"}
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
               when ':' then {"00000", "00100", "00100", "00000", "00100", "00100", "00000"}
               when '+' then {"00000", "00100", "00100", "11111", "00100", "00100", "00000"}
               when '-' then {"00000", "00000", "00000", "11111", "00000", "00000", "00000"}
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
