require "../spec_helper"
require "../../src/swanium/frontend/video_test_pattern"
require "base64"
require "compress/zlib"

private def render_test_pattern(ppu : Swanium::Core::Ppu, bus : Swanium::Core::WonderSwanBus,
                                keys : UInt16 = 0_u16) : Bytes
  Swanium::Frontend::VideoTestPattern.apply_input(bus, keys)
  bus.latch_sprites(ppu)
  Swanium::Core::Ppu::SCREEN_HEIGHT.times { |line| bus.render_scanline(ppu, line.to_u8) }
  ppu.framebuffer_rgba
end

describe Swanium::Frontend::VideoTestPattern do
  it "matches the committed full-frame RGBA image snapshot" do
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    ppu = Swanium::Core::Ppu.new
    Swanium::Frontend::VideoTestPattern.configure(bus)
    actual = render_test_pattern(ppu, bus)

    encoded = File.read(File.join(__DIR__, "..", "fixtures", "video_test_pattern.rgba.zlib.base64")).strip
    expected_io = IO::Memory.new
    Compress::Zlib::Reader.open(IO::Memory.new(Base64.decode(encoded))) { |reader| IO.copy(reader, expected_io) }
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
    Swanium::Frontend::VideoTestPattern.configure(bus)
    idle = render_test_pattern(ppu, bus).dup
    moved = render_test_pattern(ppu, bus, Swanium::Core::WonderSwanKey::X1)

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
      Swanium::Frontend::VideoTestPattern.configure(bus)

      render_test_pattern(ppu, bus, key)

      bus.read_io(0x10_u8).should eq(expected_x)
      bus.read_io(0x11_u8).should eq(expected_y)
    end
  end
end
