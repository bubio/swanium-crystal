require "../spec_helper"

describe Swanium::Core::Flags do
  it "round-trips defined FLAGS bits and preserves reserved bit one" do
    flags = Swanium::Core::Flags.from_u16(0x0FD5_u16)

    flags.to_u16.should eq(0x0FD7_u16)
  end

  it "calculates parity over the low byte" do
    Swanium::Core::Flags.parity_even?(0x00_u8).should be_true
    Swanium::Core::Flags.parity_even?(0x03_u8).should be_true
    Swanium::Core::Flags.parity_even?(0x01_u8).should be_false
  end
end
