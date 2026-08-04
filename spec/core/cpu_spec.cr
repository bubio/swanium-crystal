require "../spec_helper"

class IoMemory < Swanium::Core::FlatMemory
  getter writes = [] of Tuple(UInt8, UInt8)

  def initialize
    super
    @ports = {} of UInt8 => UInt8
  end

  def set_port(port : UInt8, value : UInt8) : Nil
    @ports[port] = value
  end

  def read_io(port : UInt8) : UInt8
    @ports[port]? || 0xFF_u8
  end

  def write_io(port : UInt8, value : UInt8) : Nil
    @writes << {port, value}
  end
end

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

  it "pushes state and loads a real-mode vector when servicing an interrupt" do
    memory = Swanium::Core::FlatMemory.new
    memory.write_u16(0x20_u32, 0x4567_u16)
    memory.write_u16(0x22_u32, 0x1234_u16)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0xABCD_u16, 0x0102_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0xFFFE_u16
    cpu.flags.interrupt = true

    cpu.service_interrupt(memory, 8_u8).should eq(10_u32)

    cpu.registers.cs.should eq(0x1234_u16)
    cpu.registers.ip.should eq(0x4567_u16)
    cpu.registers.sp.should eq(0xFFF8_u16)
    memory.read_u16(0xFFF8_u32).should eq(0x0102_u16)
    memory.read_u16(0xFFFA_u32).should eq(0xABCD_u16)
    cpu.flags.interrupt.should be_false
  end

  it "captures a restorable CPU snapshot and an instruction trace" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xB8, 0x34, 0x12])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    snapshot = cpu.snapshot

    cpu.step(memory)
    trace = cpu.last_trace.not_nil!
    trace.code_segment.should eq(0_u16)
    trace.instruction_pointer.should eq(0_u16)
    trace.opcode.should eq(0xB8_u8)
    trace.cycles.should eq(1_u32)
    cpu.registers.ax.should eq(0x1234_u16)

    cpu.restore(snapshot)
    cpu.registers.ax.should eq(0_u16)
    cpu.registers.ip.should eq(0_u16)
    cpu.last_trace.should be_nil
  end

  it "executes LOOP, direct memory MOV, and flag transfer instructions" do
    memory = Swanium::Core::FlatMemory.new
    # MOV CX,2 ; LOOP -2 ; MOV AL,[0x10] ; STC ; LAHF
    memory.load(0_u32, Bytes[0xB9, 0x02, 0x00, 0xE2, 0xFE, 0xA0, 0x10, 0x00, 0xF9, 0x9F])
    memory.write_u8(0x0010_u32, 0x5A_u8)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)

    cpu.step(memory)
    cpu.step(memory)
    cpu.registers.cx.should eq(1_u16)
    cpu.registers.ip.should eq(0x0003_u16)
    cpu.registers.cx = 0_u16
    cpu.registers.ip = 0x0005_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x5A_u8)
    cpu.step(memory)
    cpu.step(memory)
    cpu.flags.carry.should be_true
    (cpu.registers.reg8(4_u8) & 0x01_u8).should eq(0x01_u8)
  end

  it "uses TEST and XCHG without corrupting the operand contract" do
    memory = Swanium::Core::FlatMemory.new
    # XCHG AX,BX ; TEST AL,0x0F
    memory.load(0_u32, Bytes[0x93, 0xA8, 0x0F])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x1200_u16
    cpu.registers.bx = 0x00F0_u16

    cpu.step(memory)
    cpu.registers.ax.should eq(0x00F0_u16)
    cpu.registers.bx.should eq(0x1200_u16)
    cpu.step(memory)
    cpu.registers.ax.should eq(0x00F0_u16)
    cpu.flags.zero.should be_true
  end

  it "routes immediate-port IN and OUT through the memory bus" do
    memory = IoMemory.new
    memory.set_port(0x10_u8, 0x5A_u8)
    memory.load(0_u32, Bytes[0xE4, 0x10, 0xE6, 0x20])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)

    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x5A_u8)
    cpu.step(memory)
    memory.writes.should eq([{0x20_u8, 0x5A_u8}])
  end

  it "applies segment overrides to the following ModRM memory instruction" do
    memory = Swanium::Core::FlatMemory.new
    # ES: MOV AL,[0x0010]
    memory.load(0_u32, Bytes[0x26, 0x8A, 0x06, 0x10, 0x00])
    memory.write_u8(0x0110_u32, 0xAA_u8)
    memory.write_u8(0x0210_u32, 0xBB_u8)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ds = 0x0010_u16
    cpu.registers.es = 0x0020_u16

    cpu.step(memory)

    cpu.registers.reg8(0_u8).should eq(0xBB_u8)
  end

  it "copies CX bytes with REP MOVSB" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xF3, 0xA4])
    memory.write_u8(0x0010_u32, 1_u8)
    memory.write_u8(0x0011_u32, 2_u8)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.si = 0x0010_u16
    cpu.registers.di = 0x0020_u16
    cpu.registers.cx = 2_u16

    cpu.step(memory)
    memory.read_u8(0x0020_u32).should eq(1_u8)
    memory.read_u8(0x0021_u32).should eq(2_u8)
    cpu.registers.cx.should eq(0_u16)
  end

  it "repeats STOSB and LODSB with the direction flag" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xF3, 0xAA, 0xF3, 0xAC])
    memory.write_u8(0x0010_u32, 0x12_u8)
    memory.write_u8(0x0011_u32, 0x34_u8)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x005A_u16
    cpu.registers.di = 0x0021_u16
    cpu.registers.cx = 2_u16
    cpu.flags.direction = true

    cpu.step(memory)
    memory.read_u8(0x0021_u32).should eq(0x5A_u8)
    memory.read_u8(0x0020_u32).should eq(0x5A_u8)
    cpu.registers.di.should eq(0x001F_u16)
    cpu.registers.cx.should eq(0_u16)

    cpu.flags.direction = false
    cpu.registers.si = 0x0010_u16
    cpu.registers.cx = 2_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x34_u8)
    cpu.registers.si.should eq(0x0012_u16)
    cpu.registers.cx.should eq(0_u16)
  end
end
