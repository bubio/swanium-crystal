require "../spec_helper"
require "../../src/swanium/core/interrupt_controller"

describe Swanium::Core::InterruptController do
  it "returns the highest-priority enabled pending source" do
    controller = Swanium::Core::InterruptController.new
    controller.enabled_mask = 0xFF_u8
    controller.request(Swanium::Core::InterruptSource::Timer)
    controller.request(Swanium::Core::InterruptSource::VBlank)

    controller.next_pending?.should eq(Swanium::Core::InterruptSource::VBlank)
    controller.clear(Swanium::Core::InterruptSource::VBlank)
    controller.next_pending?.should eq(Swanium::Core::InterruptSource::Timer)
  end
end
