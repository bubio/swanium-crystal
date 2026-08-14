require "../spec_helper"
require "../../src/swanium/core/wave_generator"

describe Swanium::Core::WonderSwanWaveGenerator do
  it "advances enabled waveform channels from wave RAM" do
    waves = Swanium::Core::WonderSwanWaveGenerator.new
    wram = Bytes.new(0x10000, 0_u8)
    ports = Bytes.new(0x100, 0_u8)
    ports[0x90] = 0x01_u8
    wram[0] = 0xA5_u8

    waves.step(wram, ports)

    waves.sample(0).should eq(0x0A_u8)
  end
end
