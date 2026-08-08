require "../spec_helper"
require "../../src/swanium/core/pcm_sample_buffer"

describe Swanium::Core::PcmSampleBuffer do
  it "drains ownership of completed stereo frames" do
    buffer = Swanium::Core::PcmSampleBuffer.new
    buffer.append_stereo(12_i16, -34_i16)

    buffer.drain.should eq([12_i16, -34_i16])
    buffer.snapshot.should be_empty
  end
end
