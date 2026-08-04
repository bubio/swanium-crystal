require "../spec_helper"

describe Swanium::Core::Registers do
  it "maps ModRM 8-bit aliases without disturbing the other byte" do
    registers = Swanium::Core::Registers.new(ax: 0x1234_u16)

    registers.set_reg8(0_u8, 0xAB_u8)
    registers.ax.should eq(0x12AB_u16)
    registers.set_reg8(4_u8, 0xCD_u8)

    registers.ax.should eq(0xCDAB_u16)
    registers.reg8(4_u8).should eq(0xCD_u8)
  end

  it "uses the V30 segment-register encoding" do
    registers = Swanium::Core::Registers.new
    registers.set_segment(0_u8, 0x1111_u16)
    registers.set_segment(3_u8, 0x3333_u16)

    registers.es.should eq(0x1111_u16)
    registers.ds.should eq(0x3333_u16)
  end
end
