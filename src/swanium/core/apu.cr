require "./wave_generator"
require "./pcm_sample_buffer"
require "./noise_generator"
require "./voice_channel"
require "./sweep_generator"
require "./hypervoice"

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
        @sweep = WonderSwanSweepGenerator.new
        @sample_accumulator = 0_u32
        @voice = WonderSwanVoiceChannel.new
        @pcm = PcmSampleBuffer.new
      end

      def reset : Nil
        @waves.reset
        @noise.reset
        @sweep.reset
        @sample_accumulator = 0_u32
        @voice.reset
        @pcm.reset
      end

      # Channel 2 voice mode streams signed PCM through port 0x89. Games such
      # as Last Alive alternate two streams at roughly twice the audio rate;
      # the hardware's analog stage averages adjacent writes. Feeding this at
      # write time (rather than sampling the port once per audio frame) removes
      # the characteristic harsh multiplex buzz.
      def write_voice(sample : UInt8) : Nil
        @voice.write(sample)
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
          @sweep.step(ports)
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
        @sweep.save_state(io)
        io.write_bytes(@sample_accumulator, IO::ByteFormat::LittleEndian)
        @voice.save_state(io)
        @pcm.save_state(io)
      end

      def load_state(io : IO) : Nil
        @waves.load_state(io)
        @noise.load_state(io)
        @sweep.load_state(io)
        @sample_accumulator = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        @voice.load_state(io)
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
        @sweep.deactivate
        total = @sample_accumulator + cycles
        sample_count = total // CYCLES_PER_SAMPLE
        @sample_accumulator = total % CYCLES_PER_SAMPLE
        if sample_count > 0_u32
          @voice.reset
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
        @sweep.deactivate
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
        voice_left, voice_right = @voice.mix(ports, MIX_SCALE)
        left += voice_left
        right += voice_right
        if color_hardware && (ports[0x6A] & 0x80_u8) != 0_u8
          hyper_left, hyper_right = WonderSwanHyperVoice.mix(ports, MIX_SCALE)
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

      private def publish_output_ports(ports : Bytes) : Nil
        0x96_u8.upto(0x9B_u8) { |port| ports[port] = read_output_port(port, ports) }
      end
    end
  end
end
