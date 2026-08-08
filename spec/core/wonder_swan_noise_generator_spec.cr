require "../spec_helper"
require "../../src/swanium/core/wonder_swan_noise_generator"

describe Swanium::Core::WonderSwanNoiseGenerator do
  it "clocks the cartridge-visible LFSR on Color hardware" do
    noise = Swanium::Core::WonderSwanNoiseGenerator.new
    ports = Bytes.new(0x100, 0_u8)
    ports[0x8E] = 0x10_u8
    ports[0x86] = 0xFF_u8
    ports[0x87] = 0x07_u8

    noise.step(ports, true)

    noise.output.should eq(0x0F_u8)
    ports[0x92].should eq(1_u8)
  end
end
