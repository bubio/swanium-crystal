require "../spec_helper"

describe Swanium::Core::WonderSwanBus do
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
    bus.read_io(0xB4_u8).should eq(0x80_u8)
    bus.pending_interrupt_vector?.should eq(0x87_u8)

    bus.write_io(0xB6_u8, 0x80_u8)
    bus.on_vblank
    bus.pending_interrupt_vector?.should eq(0x86_u8)
    bus.write_io(0xB6_u8, 0xC0_u8)
    bus.pending_interrupt_vector?.should be_nil
  end
end
