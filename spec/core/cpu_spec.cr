require "../spec_helper"

describe Swanium::Core::Cpu do
  it "fetches little-endian instruction data and wraps IP" do
    memory = Swanium::Core::FlatMemory.new
    memory.write_u8(0x0F_FFFF_u32, 0x34_u8)
    memory.write_u8(0_u32, 0x12_u8)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0xFFFF_u16, 0x000F_u16)

    cpu.fetch_u16(memory).should eq(0x1234_u16)
    cpu.registers.ip.should eq(0x0011_u16)
  end
end
