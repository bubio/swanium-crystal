require "../spec_helper"
require "../../src/swanium/core/hypervoice"

describe Swanium::Core::WonderSwanHyperVoice do
  it "expands latched samples and applies stereo routing" do
    ports = Bytes.new(0x100, 0_u8)
    ports[0x69] = 0x20_u8
    ports[0x6B] = 0x60_u8

    Swanium::Core::WonderSwanHyperVoice.mix(ports, 32_i32).should eq({8192_i32, 8192_i32})
  end
end
