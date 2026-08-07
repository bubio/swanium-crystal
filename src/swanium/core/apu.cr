module Swanium
  module Core
    # Deterministic WonderSwan sound unit. It produces interleaved signed
    # 16-bit stereo PCM at 24 kHz from the 3.072 MHz machine clock.
    class Apu
      MASTER_CLOCK       = 3_072_000_u32
      OUTPUT_SAMPLE_RATE =    24_000_u32
      CYCLES_PER_SAMPLE  =       128_u32
      MIX_SCALE          =        32_i32

      private struct WaveChannel
        property counter : UInt16
        property index : UInt8
        property sample : UInt8

        def initialize(@counter = 0_u16, @index = 0_u8, @sample = 0_u8)
        end
      end

      getter samples : Array(Int16)

      def initialize
        @channels = StaticArray(WaveChannel, 4).new { WaveChannel.new }
        @lfsr = 0_u16
        @noise_counter = 0_u16
        @noise_output = 0_u8
        @sweep_counter = 0_u32
        @sweep_step = 0_u8
        @sample_accumulator = 0_u32
        @voice_previous = 0_i32
        @voice_level = 0_i32
        @samples = Array(Int16).new(1024)
      end

      def reset : Nil
        @channels = StaticArray(WaveChannel, 4).new { WaveChannel.new }
        @lfsr = 0_u16
        @noise_counter = 0_u16
        @noise_output = 0_u8
        @sweep_counter = 0_u32
        @sweep_step = 0_u8
        @sample_accumulator = 0_u32
        @voice_previous = 0_i32
        @voice_level = 0_i32
        @samples.clear
      end

      # Channel 2 voice mode streams signed PCM through port 0x89. Games such
      # as Last Alive alternate two streams at roughly twice the audio rate;
      # the hardware's analog stage averages adjacent writes. Feeding this at
      # write time (rather than sampling the port once per audio frame) removes
      # the characteristic harsh multiplex buzz.
      def write_voice(sample : UInt8) : Nil
        current = sample.to_i32 - 0x80
        @voice_level = (current + @voice_previous) // 2
        @voice_previous = current
      end

      def clear_samples : Nil
        @samples.clear
      end

      def tick(cycles : UInt32, wram : Bytes, ports : Bytes, color_hardware : Bool = false) : Nil
        cycles.times do
          step_sweep(ports)
          step_noise(ports)
          step_waves(wram, ports)
          @sample_accumulator += 1_u32
          if @sample_accumulator == CYCLES_PER_SAMPLE
            @sample_accumulator = 0_u32
            mix_sample(ports, color_hardware)
          end
        end
      end

      def save_state(io : IO) : Nil
        @channels.each do |channel|
          io.write_bytes(channel.counter, IO::ByteFormat::LittleEndian)
          io.write_byte(channel.index)
          io.write_byte(channel.sample)
        end
        io.write_bytes(@lfsr, IO::ByteFormat::LittleEndian)
        io.write_bytes(@noise_counter, IO::ByteFormat::LittleEndian)
        io.write_byte(@noise_output)
        io.write_bytes(@sweep_counter, IO::ByteFormat::LittleEndian)
        io.write_byte(@sweep_step)
        io.write_bytes(@sample_accumulator, IO::ByteFormat::LittleEndian)
        io.write_bytes(@voice_previous, IO::ByteFormat::LittleEndian)
        io.write_bytes(@voice_level, IO::ByteFormat::LittleEndian)
        io.write_bytes(@samples.size.to_u32, IO::ByteFormat::LittleEndian)
        @samples.each { |sample| io.write_bytes(sample, IO::ByteFormat::LittleEndian) }
      end

      def load_state(io : IO) : Nil
        @channels = StaticArray(WaveChannel, 4).new do
          WaveChannel.new(
            io.read_bytes(UInt16, IO::ByteFormat::LittleEndian),
            read_byte(io), read_byte(io)
          )
        end
        @lfsr = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
        @noise_counter = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
        @noise_output = read_byte(io)
        @sweep_counter = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        @sweep_step = read_byte(io)
        @sample_accumulator = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        @voice_previous = io.read_bytes(Int32, IO::ByteFormat::LittleEndian)
        @voice_level = io.read_bytes(Int32, IO::ByteFormat::LittleEndian)
        sample_count = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        raise ArgumentError.new("invalid buffered PCM length") if sample_count > 1_000_000_u32
        @samples = Array(Int16).new(sample_count.to_i) do
          io.read_bytes(Int16, IO::ByteFormat::LittleEndian)
        end
      end

      private def step_waves(wram : Bytes, ports : Bytes) : Nil
        control = ports[0x90]
        wave_base = ports[0x8F].to_i << 6
        4.times do |index|
          next if (control & (1_u8 << index)) == 0
          channel = @channels[index]
          channel.counter &-= 1_u16 if channel.counter > 0_u16
          if channel.counter == 0_u16
            pitch = read_pitch(ports, index)
            channel.counter = 2048_u16 - pitch
            channel.index = (channel.index &+ 1_u8) & 0x1F_u8
            address = (wave_base + index * 16 + channel.index.to_i // 2) & 0xFFFF
            byte = wram[address]
            channel.sample = (channel.index & 1_u8) == 0_u8 ? byte & 0x0F_u8 : byte >> 4
          end
          @channels[index] = channel
        end
      end

      private def step_noise(ports : Bytes) : Nil
        noise = ports[0x8E]
        if (noise & 0x08_u8) != 0_u8
          @lfsr = 0_u16
          @noise_output = 0_u8
          ports[0x8E] &= 0xF7_u8
          @noise_counter = 2048_u16 - read_pitch(ports, 3)
        end
        # The CPU-visible LFSR at 0x92/0x93 is a cartridge-visible random
        # source, not merely an audible channel-4 implementation detail.
        # Clock Tower reads it while loading with channel 4 muted; holding it
        # then leaves the game permanently on its black loading screen.
        return if (noise & 0x10_u8) == 0_u8
        @noise_counter &-= 1_u16 if @noise_counter > 0_u16
        return unless @noise_counter == 0_u16

        taps = StaticArray[14_u8, 10_u8, 13_u8, 4_u8, 8_u8, 6_u8, 9_u8, 11_u8]
        tap = taps[(noise & 0x07_u8).to_i]
        feedback = 1_u16 ^ ((@lfsr >> 7) & 1_u16) ^ ((@lfsr >> tap) & 1_u16)
        @lfsr = ((@lfsr << 1) | feedback) & 0x7FFF_u16
        @noise_output = (@lfsr & 1_u16) == 0_u16 ? 0_u8 : 0x0F_u8
        @noise_counter = 2048_u16 - read_pitch(ports, 3)
        ports[0x92] = (@lfsr & 0xFF_u16).to_u8
        ports[0x93] = (@lfsr >> 8).to_u8
      end

      private def step_sweep(ports : Bytes) : Nil
        return if (ports[0x90] & 0x44_u8) != 0x44_u8
        @sweep_counter += 1_u32
        return if @sweep_counter < 8192_u32
        @sweep_counter = 0_u32
        if @sweep_step == 0_u8
          pitch = read_pitch(ports, 2).to_i32 + ports[0x8C].to_i8.to_i32
          pitch = pitch.clamp(0, 0x7FF)
          ports[0x84] = (pitch & 0xFF).to_u8
          ports[0x85] = ((pitch >> 8) & 0x07).to_u8
          @sweep_step = ports[0x8D] & 0x1F_u8
        else
          @sweep_step &-= 1_u8
        end
      end

      private def mix_sample(ports : Bytes, color_hardware : Bool) : Nil
        control = ports[0x90]
        left = 0_i32
        right = 0_i32
        4.times do |index|
          next if (control & (1_u8 << index)) == 0
          next if index == 1 && (control & 0x20_u8) != 0_u8
          sample = index == 3 && (control & 0x80_u8) != 0_u8 ? @noise_output : @channels[index].sample
          volume = ports[0x88 + index]
          left += sample.to_i32 * (volume >> 4).to_i32 * MIX_SCALE
          right += sample.to_i32 * (volume & 0x0F_u8).to_i32 * MIX_SCALE
        end
        if (control & 0x20_u8) != 0_u8
          voice = @voice_level * MIX_SCALE * 2
          volume = ports[0x94]
          left += (volume & 0x04_u8) != 0_u8 ? voice : (volume & 0x08_u8) != 0_u8 ? voice >> 1 : 0
          right += (volume & 0x01_u8) != 0_u8 ? voice : (volume & 0x02_u8) != 0_u8 ? voice >> 1 : 0
        else
          @voice_previous = 0_i32
          @voice_level = 0_i32
        end
        if color_hardware && (ports[0x6A] & 0x80_u8) != 0_u8
          hyper_left, hyper_right = hypervoice(ports)
          left += hyper_left
          right += hyper_right
        end
        output = ports[0x91]
        unless (output & 0x80_u8) != 0_u8
          mono = (left + right) >> ((output >> 1) & 0x03_u8)
          left = mono
          right = mono
        end
        @samples << left.clamp(Int16::MIN.to_i32, Int16::MAX.to_i32).to_i16
        @samples << right.clamp(Int16::MIN.to_i32, Int16::MAX.to_i32).to_i16
      end

      private def hypervoice(ports : Bytes) : Tuple(Int32, Int32)
        direct_left = signed_word(ports[0x64], ports[0x65])
        direct_right = signed_word(ports[0x66], ports[0x67])
        return {direct_left, direct_right} if direct_left != 0 || direct_right != 0

        control = ports[0x6A]
        shift = (control & 0x03_u8).to_i32
        data = ports[0x69]
        expanded = case control & 0x0C_u8
                   when 0x00_u8 then data.to_i32 << (8 - shift)
                   when 0x04_u8 then (data.to_i32 | -0x100) << (8 - shift)
                   when 0x08_u8 then data.unsafe_as(Int8).to_i32 << (8 - shift)
                   else              data.to_i32 << 8
                   end
        sample = (expanded & 0xFFFF).to_u16.unsafe_as(Int16).to_i32 >> 5
        sample *= MIX_SCALE
        routing = ports[0x6B]
        {(routing & 0x40_u8) != 0_u8 ? sample : 0_i32,
         (routing & 0x20_u8) != 0_u8 ? sample : 0_i32}
      end

      private def signed_word(low : UInt8, high : UInt8) : Int32
        (low.to_u16 | (high.to_u16 << 8)).unsafe_as(Int16).to_i32
      end

      private def read_pitch(ports : Bytes, channel : Int32) : UInt16
        offset = 0x80 + channel * 2
        (ports[offset].to_u16 | (ports[offset + 1].to_u16 << 8)) & 0x07FF_u16
      end

      private def read_byte(io : IO) : UInt8
        io.read_byte || raise IO::EOFError.new
      end
    end
  end
end
