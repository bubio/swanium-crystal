require "../spec_helper"
require "../../src/swanium/platform/audio_resampler"

describe Swanium::Platform::AudioResampler do
  it "passes through native-rate stereo samples" do
    resampler = Swanium::Platform::AudioResampler.new(24_000, 24_000)
    resampler.process([1_i16, 2_i16, 3_i16, 4_i16]).should eq([1_i16, 2_i16, 3_i16, 4_i16])
  end

  it "interpolates 24 kHz stereo samples to 48 kHz without frame-edge resets" do
    resampler = Swanium::Platform::AudioResampler.new(24_000, 48_000)
    resampler.process([0_i16, 10_i16, 100_i16, 30_i16]).should eq([0_i16, 10_i16, 50_i16, 20_i16, 100_i16, 30_i16])
    resampler.process([200_i16, 50_i16]).should eq([150_i16, 40_i16, 200_i16, 50_i16])
  end

  it "upsamples full-scale PCM without overflowing its interpolation intermediate" do
    resampler = Swanium::Platform::AudioResampler.new(24_000, 48_000)
    resampler.process([Int16::MIN, Int16::MAX, Int16::MAX, Int16::MIN]).should eq([
      Int16::MIN, Int16::MAX,
      -1_i16, -1_i16,
      Int16::MAX, Int16::MIN,
    ])
  end
end
