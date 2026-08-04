require "../spec_helper"

describe Swanium::Core::FlatMemory do
  it "wraps 16-bit accesses at the 20-bit address-space boundary" do
    memory = Swanium::Core::FlatMemory.new

    memory.write_u16(0x0F_FFFF_u32, 0xBEEF_u16)

    memory.read_u8(0x0F_FFFF_u32).should eq(0xEF_u8)
    memory.read_u8(0_u32).should eq(0xBE_u8)
    memory.read_u16(0x0F_FFFF_u32).should eq(0xBEEF_u16)
  end

  it "resolves real-mode addresses in the 20-bit physical address space" do
    Swanium::Core.linear_address(0xFFFF_u16, 0x0010_u16).should eq(0_u32)
    Swanium::Core.linear_address(0x1234_u16, 0x5678_u16).should eq(0x179B8_u32)
  end
end
