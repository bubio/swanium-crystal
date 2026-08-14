require "../spec_helper"
require "../../src/swanium/core/palette"

describe Swanium::Core::WonderSwanPalette do
  it "resolves RGB444 palette RAM entries and Color transparency" do
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    entry = 0xFE00 + (2 * 16 + 3) * 2
    wram[entry] = 0xBC_u8
    wram[entry + 1] = 0x0A_u8

    Swanium::Core::WonderSwanPalette.resolve(wram, ports, 2_u8, 3_u8, true).should eq(0xABC_u16)
    Swanium::Core::WonderSwanPalette.transparent?(2_u8, 0_u8, true).should be_true
    Swanium::Core::WonderSwanPalette.transparent?(2_u8, 1_u8, true).should be_false
  end
end
