require "../spec_helper"

describe Swanium::Core::WonderSwanBus do
  it "returns independent snapshots instead of mutable internal buffers" do
    bus = Swanium::Core::WonderSwanBus.new(save_ram_size: 1, model: Swanium::Core::WonderSwanModel::Color)
    bus.write_u8(0_u32, 0x12_u8)
    bus.write_u8(0x10000_u32, 0x34_u8)
    bus.write_io(0x00_u8, 0x05_u8)

    ram = bus.work_ram_snapshot
    save = bus.save_ram_snapshot
    ports = bus.ports_snapshot
    ram[0] = 0_u8
    save[0] = 0_u8
    ports[0] = 0_u8

    bus.read_u8(0_u32).should eq(0x12_u8)
    bus.read_u8(0x10000_u32).should eq(0x34_u8)
    bus.read_io(0x00_u8).should eq(0x05_u8)
  end

  it "applies LCD, map, sprite, and monochrome palette port masks" do
    mono = Swanium::Core::WonderSwanBus.new
    mono.write_io(0x00_u8, 0xFF_u8)
    mono.write_io(0x04_u8, 0xFF_u8)
    mono.write_io(0x05_u8, 0xFF_u8)
    mono.write_io(0x07_u8, 0xFF_u8)
    mono.write_io(0x28_u8, 0xFF_u8)
    mono.read_io(0x00_u8).should eq(0x3F_u8)
    mono.read_io(0x04_u8).should eq(0x1F_u8)
    mono.read_io(0x05_u8).should eq(0x7F_u8)
    mono.read_io(0x07_u8).should eq(0x77_u8)
    mono.read_io(0x28_u8).should eq(0x70_u8)

    color = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Color)
    color.write_io(0x60_u8, 0x80_u8)
    color.write_io(0x04_u8, 0xFF_u8)
    color.write_io(0x07_u8, 0xFF_u8)
    color.read_io(0x04_u8).should eq(0x3F_u8)
    color.read_io(0x07_u8).should eq(0xFF_u8)
  end

  it "maps mono and Color internal RAM windows" do
    mono = Swanium::Core::WonderSwanBus.new
    mono.write_u8(0x03FFF_u32, 0x12_u8)
    mono.write_u8(0x04000_u32, 0x34_u8)
    mono.read_u8(0x03FFF_u32).should eq(0x12_u8)
    mono.read_u8(0x04000_u32).should eq(0xFF_u8)

    color = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Color)
    color.write_u8(0xFE00_u32, 0x56_u8)
    color.read_u8(0xFE00_u32).should eq(0x56_u8)
  end

  it "maps banked save RAM and cartridge ROM through the CPU-visible ports" do
    rom = Bytes.new(0x30000, 0_u8)
    rom[0x10001] = 0xA1_u8
    rom[0x20002] = 0xB2_u8
    bus = Swanium::Core::WonderSwanBus.new(rom, save_ram_size: 0x20000)
    bus.write_io(0xC1_u8, 1_u8)
    bus.write_u8(0x10010_u32, 0x44_u8)
    bus.write_io(0xC1_u8, 0_u8)
    bus.read_u8(0x10010_u32).should eq(0_u8)
    bus.write_io(0xC1_u8, 1_u8)
    bus.read_u8(0x10010_u32).should eq(0x44_u8)

    bus.write_io(0xC2_u8, 1_u8)
    bus.read_u8(0x20001_u32).should eq(0xA1_u8)
    bus.write_io(0xC3_u8, 2_u8)
    bus.read_u8(0x30002_u32).should eq(0xB2_u8)
  end

  it "uses the Bandai 2003 high-byte bank registers only for a 2003 cartridge" do
    rom = Bytes.new(0x30000, 0_u8)
    rom[0x10000] = 0xA1_u8
    footer = rom.size - 16
    rom[footer] = 0xEA_u8
    rom[footer + 13] = 1_u8
    bus = Swanium::Core::WonderSwanBus.from_cartridge(Swanium::Core::CartridgeImage.from_bytes(rom))

    bus.write_io(0xD2_u8, 0_u8)
    bus.write_io(0xD3_u8, 1_u8)
    bus.read_io(0xD3_u8).should eq(1_u8)
    bus.read_u8(0x20000_u32).should eq(0xA1_u8) # 0x0100 bank modulo 3 is bank 1

    rom[footer + 13] = 0_u8
    mapper_2001 = Swanium::Core::WonderSwanBus.from_cartridge(Swanium::Core::CartridgeImage.from_bytes(rom))
    mapper_2001.write_io(0xD3_u8, 1_u8)
    mapper_2001.read_io(0xD3_u8).should eq(0xFF_u8)
  end

  it "uses open bus for absent ROM and save RAM" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.read_u8(0x10000_u32).should eq(0xFF_u8)
    bus.read_u8(0x20000_u32).should eq(0xFF_u8)
  end

  it "latches enabled timer interrupts and chooses the highest vector" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_io(0xB0_u8, 0x80_u8)
    bus.write_io(0xB2_u8, 0xE0_u8)
    bus.write_io(0xA4_u8, 1_u8)
    bus.write_io(0xA5_u8, 0_u8)
    bus.write_io(0xA2_u8, 0x03_u8)
    bus.on_hblank
    bus.pending_interrupt_vector?.should eq(0x87_u8)
    bus.read_io(0xB4_u8).should eq(0x80_u8)
    bus.pending_interrupt_vector?.should be_nil

    bus.on_vblank
    bus.pending_interrupt_vector?.should eq(0x86_u8)
    bus.write_io(0xB6_u8, 0xC0_u8)
    bus.pending_interrupt_vector?.should be_nil
  end

  it "latches a final HBlank count when only its interrupt is enabled" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_io(0xB2_u8, 0x80_u8)
    bus.write_io(0xA4_u8, 1_u8)
    # A2 bit 0 remains clear: the final-count interrupt is the hardware quirk.
    bus.on_hblank
    bus.read_io(0xB4_u8).should eq(0x80_u8)

    disabled = Swanium::Core::WonderSwanBus.new
    disabled.write_io(0xA4_u8, 1_u8)
    disabled.on_hblank
    disabled.read_io(0xB4_u8).should eq(0_u8)
  end

  it "scans keypad groups and latches only new key presses" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_io(0xB2_u8, 0x02_u8)
    keys = Swanium::Core::WonderSwanKey::Y1 | Swanium::Core::WonderSwanKey::Y3 |
           Swanium::Core::WonderSwanKey::X2 | Swanium::Core::WonderSwanKey::A
    bus.set_keys(keys)
    bus.write_io(0xB5_u8, 0x10_u8)
    bus.read_io(0xB5_u8).should eq(0x15_u8)
    bus.write_io(0xB5_u8, 0x60_u8)
    bus.read_io(0xB5_u8).should eq(0x66_u8)
    bus.read_io(0xB4_u8).should eq(0x02_u8)

    bus.write_io(0xB6_u8, 0x02_u8)
    bus.set_keys(keys)
    bus.read_io(0xB4_u8).should eq(0_u8)
    bus.set_keys(keys | Swanium::Core::WonderSwanKey::B)
    bus.read_io(0xB4_u8).should eq(0x02_u8)
  end

  it "reports the active IRQ priority in the Mono interrupt-base readback" do
    mono = Swanium::Core::WonderSwanBus.new
    mono.write_io(0xB0_u8, 0x40_u8)
    mono.write_io(0xB2_u8, 0x82_u8)
    mono.request_interrupt(Swanium::Core::WonderSwanInterrupt::KeyPress)
    mono.request_interrupt(Swanium::Core::WonderSwanInterrupt::HBlankTimer)
    mono.read_io(0xB0_u8).should eq(0x47_u8)

    color = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Color)
    color.write_io(0xB0_u8, 0x40_u8)
    color.write_io(0xB2_u8, 0x80_u8)
    color.request_interrupt(Swanium::Core::WonderSwanInterrupt::HBlankTimer)
    color.read_io(0xB0_u8).should eq(0x40_u8)
  end

  it "reports the Color hardware flag and runs synchronous GDMA into work RAM" do
    rom = Bytes.new(0x10000, 0_u8)
    rom[0] = 0xAB_u8
    rom[1] = 0xCD_u8
    bus = Swanium::Core::WonderSwanBus.new(rom, model: Swanium::Core::WonderSwanModel::Color)
    bus.read_io(0xA0_u8).should eq(0x87_u8)
    bus.write_io(0x60_u8, 0x80_u8)
    bus.write_io(0x40_u8, 0_u8)
    bus.write_io(0x41_u8, 0_u8)
    bus.write_io(0x42_u8, 0x0F_u8)
    bus.write_io(0x44_u8, 0x10_u8)
    bus.write_io(0x45_u8, 0_u8)
    bus.write_io(0x46_u8, 2_u8)
    bus.write_io(0x47_u8, 0_u8)
    bus.write_io(0x48_u8, 0x80_u8)

    bus.read_u8(0x10_u32).should eq(0xAB_u8)
    bus.read_u8(0x11_u32).should eq(0xCD_u8)
    bus.consume_wait_cycles.should eq(7_u32)
    bus.consume_wait_cycles.should eq(0_u32)
  end

  it "matches Color HyperVoice latch and APU register semantics" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    apu = Swanium::Core::Apu.new
    bus.write_io(0x69_u8, 0x40_u8)
    bus.write_io(0x6A_u8, 0x8A_u8)
    bus.write_io(0x6B_u8, 0xFF_u8)
    bus.read_io(0x69_u8).should eq(0_u8)
    bus.read_io(0x6A_u8).should eq(0x8A_u8)
    bus.read_io(0x6B_u8).should eq(0x6F_u8)

    bus.write_io(0x64_u8, 0x34_u8)
    bus.read_io(0x69_u8).should eq(0_u8)
    bus.write_io(0x69_u8, 0x40_u8)
    bus.read_io(0x64_u8).should eq(0_u8)
    bus.read_io(0x9E_u8).should eq(0x03_u8)
    bus.write_io(0x9E_u8, 0xFF_u8)
    bus.read_io(0x9E_u8).should eq(0x03_u8)

    bus.write_u8(0_u32, 0x50_u8)
    bus.write_io(0x80_u8, 0_u8)
    bus.write_io(0x81_u8, 0xF8_u8)
    bus.write_io(0x88_u8, 0x11_u8)
    bus.write_io(0x90_u8, 0x01_u8)
    bus.tick_sound(1_u32, apu)
    bus.read_io(0x81_u8).should eq(0_u8)
    bus.read_io(0x96_u8).should eq(5_u8)
    bus.read_io(0x98_u8).should eq(5_u8)
    bus.read_io(0x9A_u8).should eq(10_u8)
  end

  it "drains each queued voice write once" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    bus.write_io(0x90_u8, 0x20_u8)
    bus.write_io(0x89_u8, 0x12_u8)
    bus.write_io(0x89_u8, 0x34_u8)

    writes = [] of UInt8
    bus.consume_voice_writes { |sample| writes << sample }
    writes.should eq([0x12_u8, 0x34_u8])

    bus.consume_voice_writes { |sample| writes << sample }
    writes.should eq([0x12_u8, 0x34_u8])
  end

  it "gates HyperVoice mixing on the Color video-mode bit" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    apu = Swanium::Core::Apu.new
    bus.write_io(0x69_u8, 0x20_u8)
    bus.write_io(0x6A_u8, 0x80_u8)
    bus.write_io(0x6B_u8, 0x40_u8)
    bus.write_io(0x91_u8, 0x80_u8)

    bus.tick_sound(128_u32, apu)
    apu.samples_snapshot.last.should eq(0_i16)
    apu.drain_samples

    bus.write_io(0x60_u8, 0x80_u8)
    bus.tick_sound(128_u32, apu)
    apu.samples_snapshot[-2].should_not eq(0_i16)
  end

  it "clocks the Crystal noise LFSR while Color rendering is disabled" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    apu = Swanium::Core::Apu.new
    bus.write_io(0x8E_u8, 0x10_u8)
    bus.write_io(0x90_u8, 0x0F_u8)

    bus.tick_sound(1_u32, apu)

    bus.read_io(0x92_u8).should_not eq(0_u8)
  end

  it "blocks GDMA from slow ROM only while the ROM-wait control bit is set" do
    rom = Bytes.new(0x10000, 0_u8)
    rom[0] = 0x5A_u8
    bus = Swanium::Core::WonderSwanBus.new(rom, model: Swanium::Core::WonderSwanModel::Crystal)
    bus.write_io(0x60_u8, 0x80_u8)
    bus.write_io(0xA0_u8, 0x08_u8)
    bus.write_io(0x42_u8, 0x08_u8)
    bus.write_io(0x44_u8, 0_u8)
    bus.write_io(0x46_u8, 2_u8)
    bus.write_io(0x48_u8, 0x80_u8)

    bus.read_io(0x46_u8).should eq(2_u8)
    bus.read_u8(0_u32).should eq(0_u8)

    bus.write_io(0xA0_u8, 0_u8)
    bus.write_io(0x48_u8, 0x80_u8)
    bus.read_io(0x46_u8).should eq(0_u8)
    bus.read_u8(0_u32).should eq(0x5A_u8)
  end

  it "applies DMA control readback masks and side effects" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    bus.write_io(0x60_u8, 0x80_u8)
    bus.write_io(0x48_u8, 0xC0_u8) # zero length completes immediately

    bus.read_io(0x48_u8).should eq(0x40_u8)
    bus.read_io(0x48_u8).should eq(0_u8)
    bus.write_io(0x42_u8, 0xFF_u8)
    bus.read_io(0x42_u8).should eq(0x0F_u8)
  end

  it "streams Color SDMA into the voice channel and completes the transfer" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    apu = Swanium::Core::Apu.new
    bus.write_io(0x60_u8, 0x80_u8)
    bus.write_u8(0x10_u32, 0xA5_u8)
    bus.write_io(0x90_u8, 0x20_u8)
    bus.write_io(0x4A_u8, 0x10_u8)
    bus.write_io(0x4B_u8, 0_u8)
    bus.write_io(0x4E_u8, 1_u8)
    bus.write_io(0x4F_u8, 0_u8)
    bus.write_io(0x52_u8, 0x83_u8)

    bus.tick_sound(128_u32, apu)

    bus.read_io(0x89_u8).should eq(0xA5_u8)
    bus.read_io(0x4A_u8).should eq(0x11_u8)
    bus.read_io(0x4E_u8).should eq(0_u8)
    bus.read_io(0x52_u8).should eq(0x03_u8)
  end

  it "supports SDMA decrement, repeat, hold, and 20-bit register masks" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    apu = Swanium::Core::Apu.new
    bus.write_io(0x60_u8, 0x80_u8)
    bus.write_io(0x4C_u8, 0xFF_u8)
    bus.write_io(0x50_u8, 0xFF_u8)
    bus.read_io(0x4C_u8).should eq(0x0F_u8)
    bus.read_io(0x50_u8).should eq(0x0F_u8)
    bus.write_io(0x4C_u8, 0_u8)
    bus.write_io(0x50_u8, 0_u8)

    bus.write_u8(0x10_u32, 0x12_u8)
    bus.write_io(0x90_u8, 0x20_u8)
    bus.write_io(0x4A_u8, 0x10_u8)
    bus.write_io(0x4E_u8, 1_u8)
    bus.write_io(0x52_u8, 0xC3_u8)
    bus.tick_sound(128_u32, apu)
    bus.read_io(0x4A_u8).should eq(0x0F_u8)

    bus.write_io(0x4A_u8, 0x10_u8)
    bus.write_io(0x4E_u8, 1_u8)
    bus.write_io(0x52_u8, 0x8B_u8)
    bus.tick_sound(128_u32, apu)
    bus.read_io(0x4A_u8).should eq(0x10_u8)
    bus.read_io(0x4E_u8).should eq(1_u8)
    bus.read_io(0x52_u8).should eq(0x8B_u8)

    bus.write_io(0x52_u8, 0x87_u8)
    bus.tick_sound(128_u32, apu)
    bus.read_io(0x89_u8).should eq(0_u8)
    bus.read_io(0x4E_u8).should eq(1_u8)
  end

  it "does not expose SDMA on original WonderSwan hardware" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_io(0x52_u8, 0x83_u8)
    bus.read_io(0x52_u8).should eq(0_u8)
  end
end
