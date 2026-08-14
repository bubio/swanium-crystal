require "../spec_helper"
require "../../src/swanium/core/voice_channel"

describe Swanium::Core::WonderSwanVoiceChannel do
  it "interpolates streamed PCM and applies stereo routing" do
    voice = Swanium::Core::WonderSwanVoiceChannel.new
    ports = Bytes.new(0x100, 0_u8)
    ports[0x90] = 0x20_u8
    ports[0x94] = 0x05_u8
    voice.write(0x90_u8)

    voice.mix(ports, 32_i32).should eq({512_i32, 512_i32})
  end
end
