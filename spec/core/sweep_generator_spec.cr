require "../spec_helper"
require "../../src/swanium/core/sweep_generator"

describe Swanium::Core::WonderSwanSweepGenerator do
  it "wraps an overflowing fast channel-three sweep" do
    sweep = Swanium::Core::WonderSwanSweepGenerator.new
    ports = Bytes.new(0x100, 0_u8)
    ports[0x90] = 0x44_u8
    ports[0x95] = 0x02_u8
    ports[0x84] = 0xFF_u8
    ports[0x85] = 0x07_u8
    ports[0x8C] = 1_u8

    sweep.step(ports)
    sweep.step(ports)

    ports[0x84].should eq(0_u8)
    ports[0x85].should eq(0_u8)
  end
end
