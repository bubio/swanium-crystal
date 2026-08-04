require "../spec_helper"
require "../../src/swanium/core/timer"

describe Swanium::Core::Timer do
  it "accumulates complete periods without depending on wall-clock time" do
    timer = Swanium::Core::Timer.new(10_u32, enabled: true)

    timer.advance(7_u32).should eq(0_u32)
    timer.counter.should eq(3_u32)
    timer.advance(23_u32).should eq(3_u32)
    timer.counter.should eq(10_u32)
  end
end
