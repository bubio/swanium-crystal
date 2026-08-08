require "./wonder_swan_wave_generator"
require "./pcm_sample_buffer"
require "./wonder_swan_noise_generator"

module Swanium
  module Core
    # Deterministic WonderSwan sound unit. It produces interleaved signed
    # 16-bit stereo PCM at 24 kHz from the 3.072 MHz machine clock.
    class Apu
      MASTER_CLOCK       = 3_072_000_u32
      OUTPUT_SAMPLE_RATE =    24_000_u32
      CYCLES_PER_SAMPLE  =       128_u32
      MIX_SCALE          =        32_i32

      def initialize
        @waves = WonderSwanWaveGenerator.new
        @noise = WonderSwanNoiseGenerator.new
        @sweep_counter = 0_u32
        @sweep_step = 0_u8
        @fast_sweep_primed = false
        @sample_accumulator = 0_u32
        @voice_previous = 0_i32
        @voice_level = 0_i32
        @pcm = PcmSampleBuffer.new
      end

      def reset : Nil
        @waves.reset
        @noise.reset
        @sweep_counter = 0_u32
        @sweep_step = 0_u8
        @fast_sweep_primed = false
        @sample_accumulator = 0_u32
        @voice_previous = 0_i32
        @voice_level = 0_i32
        @pcm.reset
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

      # CPU-visible digital mixer registers 0x96--0x9B are derived from the
      # current oscillator state; they are not ordinary writable latches.
      def read_output_port(port : UInt8, ports : Bytes) : UInt8
        raise ArgumentError.new("invalid APU output port") unless port.in?(0x96_u8..0x9B_u8)

        control = ports[0x90]
        left = 0_u16
        right = 0_u16
        4.times do |index|
          next if (control & (1_u8 << index)) == 0_u8
          next if index == 1 && (control & 0x20_u8) != 0_u8

          sample = index == 3 && (control & 0x80_u8) != 0_u8 ? @noise.output : @waves.sample(index)
          volume = ports[0x88 + index]
          left &+= sample.to_u16 * (volume >> 4).to_u16
          right &+= sample.to_u16 * (volume & 0x0F_u8).to_u16
        end
        if (control & 0x20_u8) != 0_u8
          voice = ports[0x89].to_u16
          left &+= voice
          right &+= voice
        end

        value = case port & 0xFE_u8
                when 0x96_u8 then right
                when 0x98_u8 then left
                else              left &+ right
                end
        (port & 1_u8) == 0_u8 ? (value & 0x00FF_u16).to_u8 : (value >> 8).to_u8
      end

      def reset_noise_lfsr(ports : Bytes) : Nil
        @noise.reset_lfsr(ports)
      end

      # Returns a copy for inspection without exposing the APU's producer
      # buffer to callers.
      def samples_snapshot : Array(Int16)
        @pcm.snapshot
      end

      # Transfers the completed PCM buffer to the audio backend and starts a
      # fresh producer buffer. This makes consuming audio a single operation
      # instead of relying on callers to remember a separate clear step.
      def drain_samples : Array(Int16)
        @pcm.drain
      end

      def tick(cycles : UInt32, wram : Bytes, ports : Bytes, color_hardware : Bool = false,
               color_rendering_enabled : Bool = color_hardware) : Nil
        if silent_fast_path?(ports, color_rendering_enabled)
          tick_silence(cycles, ports)
          return
        end
        if wave_only_fast_path?(ports, color_rendering_enabled)
          tick_waves_only(cycles, wram, ports, color_rendering_enabled)
          return
        end

        cycles.times do
          step_sweep(ports)
          @noise.step(ports, color_hardware)
          @waves.step(wram, ports)
          @sample_accumulator += 1_u32
          if @sample_accumulator == CYCLES_PER_SAMPLE
            @sample_accumulator = 0_u32
            mix_sample(ports, color_rendering_enabled)
          end
        end
        publish_output_ports(ports)
      end

      def save_state(io : IO) : Nil
        @waves.save_state(io)
        @noise.save_state(io)
        io.write_bytes(@sweep_counter, IO::ByteFormat::LittleEndian)
        io.write_byte(@sweep_step)
        io.write_byte(@fast_sweep_primed ? 1_u8 : 0_u8)
        io.write_bytes(@sample_accumulator, IO::ByteFormat::LittleEndian)
        io.write_bytes(@voice_previous, IO::ByteFormat::LittleEndian)
        io.write_bytes(@voice_level, IO::ByteFormat::LittleEndian)
        @pcm.save_state(io)
      end

      def load_state(io : IO) : Nil
        @waves.load_state(io)
        @noise.load_state(io)
        @sweep_counter = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        @sweep_step = read_byte(io)
        @fast_sweep_primed = read_byte(io) != 0_u8
        @sample_accumulator = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        @voice_previous = io.read_bytes(Int32, IO::ByteFormat::LittleEndian)
        @voice_level = io.read_bytes(Int32, IO::ByteFormat::LittleEndian)
        @pcm.load_state(io)
      end

      # With every sound source disabled, the per-cycle oscillator work has no
      # observable effect. Keep the sample clock and output register shadow in
      # lockstep while skipping the empty channel scan. A noise reset or an
      # open noise gate must use the normal path: Crystal software such as
      # Clock Tower reads the LFSR even while channel four is inaudible.
      private def silent_fast_path?(ports : Bytes, color_rendering_enabled : Bool) : Bool
        ports[0x90] == 0_u8 &&
          (ports[0x8E] & 0x18_u8) == 0_u8 &&
          (!color_rendering_enabled || (ports[0x6A] & 0x80_u8) == 0_u8)
      end

      private def tick_silence(cycles : UInt32, ports : Bytes) : Nil
        @fast_sweep_primed = false
        total = @sample_accumulator + cycles
        sample_count = total // CYCLES_PER_SAMPLE
        @sample_accumulator = total % CYCLES_PER_SAMPLE
        if sample_count > 0_u32
          @voice_previous = 0_i32
          @voice_level = 0_i32
          @pcm.append_silence(sample_count)
        end
        0x96_u8.upto(0x9B_u8) { |port| ports[port] = 0_u8 }
      end

      # This path retains ordinary wave generators but has no source whose
      # state must be checked on every cycle. Advance each channel directly to
      # the next PCM sampling boundary, preserving the same counter-underflow
      # and waveform-index behaviour as step_waves.
      private def wave_only_fast_path?(ports : Bytes, color_rendering_enabled : Bool) : Bool
        (ports[0x90] & 0xE0_u8) == 0_u8 &&
          (ports[0x8E] & 0x18_u8) == 0_u8 &&
          (!color_rendering_enabled || (ports[0x6A] & 0x80_u8) == 0_u8)
      end

      private def tick_waves_only(cycles : UInt32, wram : Bytes, ports : Bytes,
                                  color_rendering_enabled : Bool) : Nil
        @fast_sweep_primed = false
        remaining = cycles
        while remaining > 0_u32
          until_sample = CYCLES_PER_SAMPLE - @sample_accumulator
          chunk = remaining < until_sample ? remaining : until_sample
          @waves.advance(chunk, wram, ports)
          @sample_accumulator += chunk
          remaining -= chunk
          if @sample_accumulator == CYCLES_PER_SAMPLE
            @sample_accumulator = 0_u32
            mix_sample(ports, color_rendering_enabled)
          end
        end
        publish_output_ports(ports)
      end

      private def step_sweep(ports : Bytes) : Nil
        unless (ports[0x90] & 0x44_u8) == 0x44_u8
          @fast_sweep_primed = false
          return
        end

        fast = (ports[0x95] & 0x02_u8) != 0_u8
        if fast
          unless @fast_sweep_primed
            @fast_sweep_primed = true
            return
          end
        else
          @fast_sweep_primed = false
        end
        @sweep_counter += 1_u32
        return if @sweep_counter <= (fast ? 0_u32 : 8192_u32)
        @sweep_counter = 0_u32
        if @sweep_step != 0_u8
          @sweep_step &-= 1_u8
          return
        end
        @sweep_step = ports[0x8D] & 0x1F_u8
        @sweep_step &-= 1_u8 if @sweep_step > 0_u8

        # Sweep overflow wraps to the opposite edge, rather than saturating.
        # This is the V30-compatible hardware behavior exercised by ws-test.
        pitch = read_pitch(ports, 2).to_i32 + ports[0x8C].unsafe_as(Int8).to_i32
        pitch = pitch > 0x7FF ? 0 : pitch < 0 ? 0x7FF : pitch
        ports[0x84] = (pitch & 0xFF).to_u8
        ports[0x85] = ((pitch >> 8) & 0x07).to_u8
      end

      private def mix_sample(ports : Bytes, color_hardware : Bool) : Nil
        control = ports[0x90]
        left = 0_i32
        right = 0_i32
        4.times do |index|
          next if (control & (1_u8 << index)) == 0
          next if index == 1 && (control & 0x20_u8) != 0_u8
          sample = index == 3 && (control & 0x80_u8) != 0_u8 ? @noise.output : @waves.sample(index)
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
        @pcm.append_stereo(
          left.clamp(Int16::MIN.to_i32, Int16::MAX.to_i32).to_i16,
          right.clamp(Int16::MIN.to_i32, Int16::MAX.to_i32).to_i16
        )
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

      private def publish_output_ports(ports : Bytes) : Nil
        0x96_u8.upto(0x9B_u8) { |port| ports[port] = read_output_port(port, ports) }
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
