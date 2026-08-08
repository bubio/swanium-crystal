require "../spec_helper"
require "../../src/swanium/core/video_test_pattern"
require "base64"
require "compress/zlib"

describe Swanium::Core::Ppu do
  it "renders mono 2bpp tiles through the shade pool" do
    bus = Swanium::Core::WonderSwanBus.new
    ppu = Swanium::Core::Ppu.new
    bus.write_io(0x00_u8, 0x01_u8)
    bus.write_io(0x1C_u8, 0x0F_u8) # pool 0 = black, pool 1 = white
    bus.write_io(0x20_u8, 0x10_u8) # pixel 0 -> pool 0, pixel 1 -> pool 1
    bus.write_u8(0x2000_u32, 0x80_u8)

    bus.render_scanline(ppu, 0_u8)

    ppu.pixel_rgb444(0, 0).should eq(0x0FFF_u16)
    ppu.pixel_rgb444(1, 0).should eq(0x0000_u16)
  end

  it "supports packed and planar Color/Crystal 4bpp pixels" do
    [0xC0_u8, 0xE0_u8].each do |mode|
      bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
      ppu = Swanium::Core::Ppu.new
      bus.write_io(0x60_u8, mode)
      bus.write_io(0x00_u8, 0x01_u8)
      color = 0x0A5C_u16
      address = 0xFE00 + 5 * 2
      bus.write_u8(address.to_u32, (color & 0xFF).to_u8)
      bus.write_u8((address + 1).to_u32, (color >> 8).to_u8)
      if mode == 0xE0_u8
        bus.write_u8(0x4000_u32, 0x50_u8)
      else
        bus.write_u8(0x4000_u32, 0x80_u8) # planes 0 and 2
        bus.write_u8(0x4002_u32, 0x80_u8)
      end

      bus.render_scanline(ppu, 0_u8)
      ppu.pixel_rgb444(0, 0).should eq(color)
    end
  end

  it "composites a front-priority sprite and converts RGB444 to RGBA8888" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Color)
    ppu = Swanium::Core::Ppu.new
    bus.write_io(0x60_u8, 0xE0_u8)
    bus.write_io(0x00_u8, 0x04_u8)
    bus.write_io(0x04_u8, 0x10_u8)
    bus.write_io(0x06_u8, 1_u8)
    bus.write_u8(0x2000_u32, 0x01_u8)
    bus.write_u8(0x2001_u32, 0x22_u8) # palette 1 + front priority
    bus.write_u8(0x2002_u32, 0_u8)
    bus.write_u8(0x2003_u32, 0_u8)
    bus.write_u8(0x4020_u32, 0x30_u8)
    color_address = 0xFE00 + (9 * 16 + 3) * 2
    bus.write_u8(color_address.to_u32, 0xBC_u8)
    bus.write_u8((color_address + 1).to_u32, 0x0A_u8)

    bus.render_scanline(ppu, 0_u8)

    ppu.pixel_rgb444(0, 0).should eq(0x0ABC_u16)
    ppu.framebuffer_rgba[0, 4].should eq(Bytes[0xAA, 0xBB, 0xCC, 0xFF])
    ppu.framebuffer_rgba.same?(ppu.framebuffer_rgba).should be_true
  end

  it "clips SCR2 to its inclusive display window" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Color)
    ppu = Swanium::Core::Ppu.new
    bus.write_io(0x60_u8, 0xE0_u8)
    bus.write_io(0x00_u8, 0x22_u8) # SCR2 + inside-window mode
    bus.write_io(0x08_u8, 1_u8)
    bus.write_io(0x09_u8, 0_u8)
    bus.write_io(0x0A_u8, 2_u8)
    bus.write_io(0x0B_u8, 0_u8)
    bus.write_u8(0x4000_u32, 0x11_u8)
    bus.write_u8(0x4001_u32, 0x11_u8)
    bus.write_u8(0x4002_u32, 0x11_u8)
    bus.write_u8(0x4003_u32, 0x11_u8)
    bus.write_u8(0xFE00_u32, 0x23_u8)
    bus.write_u8(0xFE01_u32, 0x01_u8)
    bus.write_u8(0xFE02_u32, 0x56_u8)
    bus.write_u8(0xFE03_u32, 0x04_u8)

    bus.render_scanline(ppu, 0_u8)

    ppu.pixel_rgb444(0, 0).should eq(0x0123_u16)
    ppu.pixel_rgb444(1, 0).should eq(0x0456_u16)
    ppu.pixel_rgb444(2, 0).should eq(0x0456_u16)
    ppu.pixel_rgb444(3, 0).should eq(0x0123_u16)
  end

  it "matches the committed full-frame RGBA image snapshot" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    ppu = Swanium::Core::Ppu.new
    Swanium::Core::VideoTestPattern.configure(bus)
    actual = Swanium::Core::VideoTestPattern.render(ppu, bus)

    encoded = File.read(File.join(__DIR__, "..", "fixtures", "video_test_pattern.rgba.zlib.base64")).strip
    compressed = Base64.decode(encoded)
    expected_io = IO::Memory.new
    Compress::Zlib::Reader.open(IO::Memory.new(compressed)) do |reader|
      IO.copy(reader, expected_io)
    end
    expected = expected_io.to_slice

    actual.size.should eq(Swanium::Core::Ppu::PIXEL_COUNT * 4)
    if actual != expected
      mismatch = actual.size.times.find { |index| actual[index] != expected[index] }
      fail "RGBA snapshot differs at byte #{mismatch} (actual #{actual[mismatch.not_nil!]}, expected #{expected[mismatch.not_nil!]})"
    end
  end

  it "changes the verification frame in response to directional input" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    ppu = Swanium::Core::Ppu.new
    Swanium::Core::VideoTestPattern.configure(bus)
    idle = Swanium::Core::VideoTestPattern.render(ppu, bus).dup
    moved = Swanium::Core::VideoTestPattern.render(ppu, bus, Swanium::Core::WonderSwanKey::X1)

    moved.should_not eq(idle)
    bus.keys.should eq(Swanium::Core::WonderSwanKey::X1)
  end

  it "wraps all four directional scroll inputs without conversion errors" do
    cases = [
      {Swanium::Core::WonderSwanKey::X1, 2_u8, 0_u8},
      {Swanium::Core::WonderSwanKey::X2, 0_u8, 2_u8},
      {Swanium::Core::WonderSwanKey::X3, 254_u8, 0_u8},
      {Swanium::Core::WonderSwanKey::X4, 0_u8, 254_u8},
    ]

    cases.each do |key, expected_x, expected_y|
      bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
      ppu = Swanium::Core::Ppu.new
      Swanium::Core::VideoTestPattern.configure(bus)

      Swanium::Core::VideoTestPattern.render(ppu, bus, key)

      bus.read_io(0x10_u8).should eq(expected_x)
      bus.read_io(0x11_u8).should eq(expected_y)
    end
  end
end
