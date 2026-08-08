require "../spec_helper"
require "../../src/swanium/core/v30_address_decoder"

describe Swanium::Core::V30AddressDecoder do
  it "decodes a signed ModRM displacement without mutating CPU state" do
    memory = Swanium::Core::FlatMemory.new
    registers = Swanium::Core::Registers.new(cs: 0_u16, ds: 0x12_u16, bx: 0x100_u16, si: 5_u16)
    memory.write_u8(0_u32, 0x40_u8) # mod=01, reg=00, [BX + SI + disp8]
    memory.write_u8(1_u32, 0xFE_u8)

    mod_rm, next_ip = Swanium::Core::V30AddressDecoder.decode_mod_rm(memory, registers, nil)

    mod_rm.reg.should eq(0_u8)
    mod_rm.operand.memory?.should eq(Swanium::Core.linear_address(0x12_u16, 0x103_u16))
    next_ip.should eq(2_u16)
    registers.ip.should eq(0_u16)
  end
end
