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

  it "executes immediate MOV and ALU instructions with V30 flags" do
    memory = Swanium::Core::FlatMemory.new
    # MOV AX,0x7FFF ; ADD AX,1 ; CMP AX,0x8000
    memory.load(0_u32, Bytes[0xB8, 0xFF, 0x7F, 0x05, 0x01, 0x00, 0x3D, 0x00, 0x80])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)

    cpu.step(memory).should eq(1_u32)
    cpu.step(memory).should eq(1_u32)
    cpu.registers.ax.should eq(0x8000_u16)
    cpu.flags.overflow.should be_true
    cpu.flags.sign.should be_true
    cpu.step(memory).should eq(1_u32)
    cpu.flags.zero.should be_true
  end

  it "uses DS for ordinary ModRM addresses and SS for BP-based addresses" do
    memory = Swanium::Core::FlatMemory.new
    # MOV [0x0010], AL ; MOV [BP+SI], AH
    memory.load(0_u32, Bytes[0x88, 0x06, 0x10, 0x00, 0x88, 0x22])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0xABCD_u16
    cpu.registers.ds = 0x0010_u16
    cpu.registers.ss = 0x0020_u16
    cpu.registers.bp = 0x0002_u16
    cpu.registers.si = 0x0003_u16

    cpu.step(memory)
    cpu.step(memory)

    memory.read_u8(0x0110_u32).should eq(0xCD_u8)
    memory.read_u8(0x0205_u32).should eq(0xAB_u8)
  end

  it "preserves a return address across CALL and RET" do
    memory = Swanium::Core::FlatMemory.new
    # CALL +2 ; HLT ; NOP ; RET
    memory.load(0_u32, Bytes[0xE8, 0x02, 0x00, 0xF4, 0x90, 0xC3])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0xFFFE_u16

    cpu.step(memory)
    cpu.registers.ip.should eq(0x0005_u16)
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0003_u16)
    cpu.step(memory)
    cpu.halted.should be_true
  end

  it "takes conditional branches and records unsupported opcodes deterministically" do
    memory = Swanium::Core::FlatMemory.new
    # JE +2 ; HLT ; HLT
    memory.load(0_u32, Bytes[0x74, 0x02, 0xF4, 0xF4])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.flags.zero = true

    cpu.step(memory).should eq(5_u32)
    cpu.registers.ip.should eq(0x0004_u16)

    unsupported = Swanium::Core::FlatMemory.new
    unsupported.write_u8(0_u32, 0x0F_u8)
    cpu.reset(0_u16, 0_u16)
    cpu.step(unsupported)
    cpu.halted.should be_true
    cpu.fault_opcode.should eq(0x0F_u8)
  end
end
