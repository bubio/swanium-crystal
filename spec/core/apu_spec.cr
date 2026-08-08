require "digest/sha256"
require "../spec_helper"

describe Swanium::Core::Apu do
  it "emits 24 kHz interleaved stereo at one sample per 128 cycles" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)

    apu.tick(127_u32, wram, ports)
    apu.samples.should be_empty
    apu.tick(1_u32, wram, ports, true)
    apu.samples.should eq([0_i16, 0_i16])
  end

  it "fast-forwards silent audio while keeping sample timing and output ports" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x96] = 0xFF_u8

    apu.tick(127_u32, wram, ports)
    apu.samples.should be_empty
    ports[0x96].should eq(0_u8)

    apu.tick(1_u32, wram, ports)
    apu.samples.should eq([0_i16, 0_i16])
  end

  it "keeps a deterministic PCM hash for the audio test waveform" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    16.times { |index| wram[0x200 + index] = index < 8 ? 0x00_u8 : 0xFF_u8 }
    pitch = 1830_u16
    ports[0x80] = (pitch & 0xFF_u16).to_u8
    ports[0x81] = (pitch >> 8).to_u8
    ports[0x88] = 0x22_u8
    ports[0x8F] = 8_u8
    ports[0x90] = 0x01_u8
    ports[0x91] = 0x80_u8

    apu.tick(Swanium::Core::Machine::CYCLES_PER_FRAME.to_u32, wram, ports)
    bytes = Slice.new(apu.samples.to_unsafe.as(UInt8*), apu.samples.size * sizeof(Int16))
    Digest::SHA256.hexdigest(bytes).should eq("bf8c81726fb908f2f73768afb2a8f629f91837daa9e5710e7c10569a6828fd87")
  end

  it "preserves wave phase when a channel advances every cycle" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    wram[0x200] = 0x21_u8
    ports[0x80] = 0xFF_u8
    ports[0x81] = 0x07_u8
    ports[0x88] = 0x11_u8
    ports[0x8F] = 8_u8
    ports[0x90] = 0x01_u8

    apu.tick(128_u32, wram, ports)

    # 128 steps wraps the 32-sample wave index to zero, whose low nibble is 1.
    # The speaker path sums the equal left/right contributions.
    apu.samples.should eq([64_i16, 64_i16])
  end

  it "updates sweep and noise state through hardware ports" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x84] = 0x00_u8
    ports[0x85] = 0x04_u8
    ports[0x8C] = 1_u8
    ports[0x8D] = 0_u8
    ports[0x8E] = 0x18_u8
    ports[0x90] = 0xCC_u8

    apu.tick(8193_u32, wram, ports)
    (ports[0x84].to_u16 | (ports[0x85].to_u16 << 8)).should eq(0x0401_u16)
    (ports[0x92].to_u16 | (ports[0x93].to_u16 << 8)).should_not eq(0_u16)
    ports[0x8E].bit(3).should eq(0)
  end

  it "accepts a negative signed sweep delta" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x84] = 0x00_u8
    ports[0x85] = 0x04_u8
    ports[0x8C] = 0xFF_u8 # -1 as signed 8-bit hardware data.
    ports[0x8D] = 0_u8
    ports[0x90] = 0x44_u8 # Channel three and sweep enabled.

    apu.tick(8193_u32, wram, ports)

    (ports[0x84].to_u16 | (ports[0x85].to_u16 << 8)).should eq(0x03FF_u16)
  end

  it "advances the noise LFSR for CPU readback while channel four is muted" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x8E] = 0x10_u8 # Noise gate only; channel 4 output stays muted.
    ports[0x90] = 0x08_u8

    apu.tick(1_u32, wram, ports, true)

    ports[0x92].should eq(1_u8)
    ports[0x93].should eq(0_u8)
  end

  it "matches the Rust sweep threshold, fast test mode, and overflow wrap" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x84] = 0_u8
    ports[0x85] = 1_u8
    ports[0x8C] = 5_u8
    ports[0x8D] = 1_u8
    ports[0x90] = 0x44_u8
    apu.tick(8192_u32, wram, ports)
    (ports[0x84].to_u16 | (ports[0x85].to_u16 << 8)).should eq(0x100_u16)
    apu.tick(1_u32, wram, ports)
    (ports[0x84].to_u16 | (ports[0x85].to_u16 << 8)).should eq(0x105_u16)

    apu.reset
    ports.fill(0_u8)
    ports[0x8C] = 1_u8
    ports[0x90] = 0x44_u8
    ports[0x95] = 0x02_u8
    apu.tick(6_u32, wram, ports)
    ports[0x84].should eq(5_u8)

    apu.reset
    ports.fill(0_u8)
    ports[0x84] = 0xFF_u8
    ports[0x85] = 0x07_u8
    ports[0x8C] = 1_u8
    ports[0x90] = 0x44_u8
    apu.tick(8193_u32, wram, ports)
    ports[0x84].should eq(0_u8)
    ports[0x85].should eq(0_u8)
  end

  it "reconstructs multiplexed channel-two PCM from every port write" do
    apu = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x90] = 0x20_u8 # Voice mode.
    ports[0x91] = 0x80_u8 # Stereo output.
    ports[0x94] = 0x05_u8 # Full volume on both sides.

    apu.write_voice(0xC0_u8)
    apu.tick(128_u32, wram, ports)
    apu.samples.should eq([2048_i16, 2048_i16])
    apu.clear_samples

    apu.write_voice(0xC0_u8)
    apu.tick(128_u32, wram, ports)
    apu.samples.should eq([4096_i16, 4096_i16])
  end

  it "matches headless APU advancement with instruction-driven machine advancement" do
    direct = Swanium::Core::Apu.new
    direct_wram = Bytes.new(0x10000, 0_u8)
    direct_ports = Bytes.new(0x100, 0_u8)
    machine = Swanium::Core::Machine.new
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    128.times { |index| bus.write_u8(index.to_u32, 0x90_u8) }

    direct.tick(128_u32, direct_wram, direct_ports)
    128.times { machine.step_wonder_swan(bus) }

    machine.apu.samples.should eq(direct.samples)
    machine.cycles.should eq(128_u64)
  end

  it "gates HyperVoice stereo PCM to Color hardware" do
    mono = Swanium::Core::Apu.new
    color = Swanium::Core::Apu.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x69] = 0x20_u8
    ports[0x6A] = 0x80_u8
    ports[0x6B] = 0x40_u8
    ports[0x91] = 0x80_u8

    mono.tick(128_u32, wram, ports, false)
    color.tick(128_u32, wram, ports, true)

    mono.samples.should eq([0_i16, 0_i16])
    color.samples.should eq([8192_i16, 0_i16])
  end
end
