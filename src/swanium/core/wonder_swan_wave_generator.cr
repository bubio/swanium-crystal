module Swanium
  module Core
    # Owns the four programmable waveform oscillators. Mixer policy and the
    # noise/voice generators remain in Apu; this device advances only wave RAM
    # playback state.
    class WonderSwanWaveGenerator
      private struct Channel
        property counter : UInt16
        property index : UInt8
        property sample : UInt8

        def initialize(@counter = 0_u16, @index = 0_u8, @sample = 0_u8)
        end
      end

      def initialize
        @channels = StaticArray(Channel, 4).new { Channel.new }
      end

      def reset : Nil
        @channels = StaticArray(Channel, 4).new { Channel.new }
      end

      def sample(index : Int32) : UInt8
        @channels[index].sample
      end

      def step(wram : Bytes, ports : Bytes) : Nil
        control = ports[0x90]
        wave_base = ports[0x8F].to_i << 6
        4.times do |index|
          next if (control & (1_u8 << index)) == 0_u8
          channel = @channels[index]
          channel.counter &-= 1_u16 if channel.counter > 0_u16
          if channel.counter == 0_u16
            channel.counter = 2048_u16 - pitch(ports, index)
            channel.index = (channel.index &+ 1_u8) & 0x1F_u8
            channel.sample = wave_sample(wram, wave_base, index, channel.index)
          end
          @channels[index] = channel
        end
      end

      def advance(cycles : UInt32, wram : Bytes, ports : Bytes) : Nil
        control = ports[0x90]
        wave_base = ports[0x8F].to_i << 6
        4.times do |index|
          next if (control & (1_u8 << index)) == 0_u8
          advance_channel(index, cycles, wram, ports, wave_base)
        end
      end

      def save_state(io : IO) : Nil
        @channels.each do |channel|
          io.write_bytes(channel.counter, IO::ByteFormat::LittleEndian)
          io.write_byte(channel.index)
          io.write_byte(channel.sample)
        end
      end

      def load_state(io : IO) : Nil
        @channels = StaticArray(Channel, 4).new do
          Channel.new(
            io.read_bytes(UInt16, IO::ByteFormat::LittleEndian),
            read_byte(io), read_byte(io)
          )
        end
      end

      private def advance_channel(index : Int32, cycles : UInt32, wram : Bytes,
                                  ports : Bytes, wave_base : Int32) : Nil
        channel = @channels[index]
        remaining = cycles
        period = 2048_u16 - pitch(ports, index)
        while remaining > 0_u32
          until_next = channel.counter == 0_u16 ? 1_u32 : channel.counter.to_u32
          if until_next > remaining
            channel.counter -= remaining.to_u16
            break
          end
          remaining -= until_next
          channel.counter = period
          channel.index = (channel.index &+ 1_u8) & 0x1F_u8
          channel.sample = wave_sample(wram, wave_base, index, channel.index)
        end
        @channels[index] = channel
      end

      private def wave_sample(wram : Bytes, wave_base : Int32, channel : Int32, index : UInt8) : UInt8
        address = (wave_base + channel * 16 + index.to_i // 2) & 0xFFFF
        byte = wram[address]
        (index & 1_u8) == 0_u8 ? byte & 0x0F_u8 : byte >> 4
      end

      private def pitch(ports : Bytes, channel : Int32) : UInt16
        offset = 0x80 + channel * 2
        (ports[offset].to_u16 | (ports[offset + 1].to_u16 << 8)) & 0x07FF_u16
      end

      private def read_byte(io : IO) : UInt8
        io.read_byte || raise IO::EOFError.new
      end
    end
  end
end
