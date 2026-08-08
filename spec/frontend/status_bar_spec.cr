require "../spec_helper"
require "../../src/swanium/frontend/status_bar"

describe Swanium::Frontend::StatusBar do
  it "preserves the frame and adds a status strip with volume controls" do
    width = 224
    height = 144
    frame = Bytes.new(width * height * 4, 0x7F_u8)
    destination = Bytes.new(width * (height + Swanium::Frontend::StatusBar::HEIGHT) * 4, 0_u8)

    Swanium::Frontend::StatusBar.render(destination, frame, width, height, "test.wsc", 59.6, false, 50)

    destination[0, frame.size].should eq(frame)
    bar_offset = frame.size
    destination[bar_offset, 3].should eq(Bytes[0x1E_u8, 0x1E_u8, 0x1E_u8])
    destination.should_not eq(Bytes.new(destination.size, 0_u8))
  end

  it "rejects buffers that cannot contain the full bar" do
    expect_raises(ArgumentError) do
      Swanium::Frontend::StatusBar.render(Bytes.new(1), Bytes.new(1), 1, 1, "demo", 60.0, false, 100)
    end
  end
end
