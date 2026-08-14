module Swanium
  module Core
    # Preserves the LCD's frame-boundary sprite snapshots independently from
    # scanline compositing. PPU owns rendering; this device owns the two
    # hardware sprite buffers and their serialized state.
    class WonderSwanSpriteLatch
      struct Sprite
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

      getter current_count : Int32

      def initialize
        @current = Array(Sprite).new(128) { Sprite.new }
        @next = Array(Sprite).new(128) { Sprite.new }
        @current_count = 0
        @next_count = 0
        @current_valid = false
      end

      def reset : Nil
        @current_count = 0
        @next_count = 0
        @current_valid = false
      end

      def latch_current_if_needed(wram : Bytes, ports : Bytes) : Nil
        return if @current_valid

        @current_count = latch(wram, ports, @current)
        @current_valid = true
      end

      def capture_next(wram : Bytes, ports : Bytes) : Nil
        @next_count = latch(wram, ports, @next)
      end

      def promote_next : Nil
        i = 0
        while i < @next_count
          @current[i] = @next[i]
          i += 1
        end
        @current_count = @next_count
        @current_valid = true
      end

      def current_at(index : Int32) : Sprite
        @current[index]
      end

      def save_metadata(io : IO) : Nil
        io.write_bytes(@current_count.to_u16, IO::ByteFormat::LittleEndian)
        io.write_bytes(@next_count.to_u16, IO::ByteFormat::LittleEndian)
        io.write_byte(@current_valid ? 1_u8 : 0_u8)
      end

      def save_buffers(io : IO) : Nil
        write_sprites(io, @current)
        write_sprites(io, @next)
      end

      def load_metadata(io : IO) : Nil
        current_count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian).to_i
        next_count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian).to_i
        current_valid = read_byte(io)
        unless current_count <= 128 && next_count <= 128 && current_valid <= 1_u8
          raise ArgumentError.new("invalid sprite latch state")
        end

        @current_count = current_count
        @next_count = next_count
        @current_valid = current_valid == 1_u8
      end

      def load_buffers(io : IO) : Nil
        @current = read_sprites(io)
        @next = read_sprites(io)
      end

      private def latch(wram : Bytes, ports : Bytes, target : Array(Sprite)) : Int32
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
        count
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
    end
  end
end
