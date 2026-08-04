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

private def cpu_with(code : Bytes) : Tuple(Swanium::Core::Cpu, Swanium::Core::FlatMemory)
  memory = Swanium::Core::FlatMemory.new
  memory.load(0_u32, code)
  cpu = Swanium::Core::Cpu.new
  cpu.reset(0_u16, 0_u16)
  cpu.registers.ss = 0_u16
  cpu.registers.sp = 0xFFFE_u16
  {cpu, memory}
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

  it "fetches both immediate words before applying a far jump" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xEA, 0x34, 0x12, 0x78, 0x56])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)

    cpu.step(memory)

    cpu.registers.cs.should eq(0x5678_u16)
    cpu.registers.ip.should eq(0x1234_u16)
  end

  it "takes conditional branches" do
    memory = Swanium::Core::FlatMemory.new
    # JE +2 ; HLT ; HLT
    memory.load(0_u32, Bytes[0x74, 0x02, 0xF4, 0xF4])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.flags.zero = true

    cpu.step(memory).should eq(5_u32)
    cpu.registers.ip.should eq(0x0004_u16)
  end

  it "uses the address after its immediate byte as the short jump base" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xEB, 0x00, 0x90])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)

    cpu.step(memory)

    cpu.registers.ip.should eq(0x0002_u16)
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

  it "executes V30 shifts, rotates, and XLAT" do
    memory = Swanium::Core::FlatMemory.new
    # SHL AL,1 ; SHR AX,CL ; ROL AL,1 ; SAR AL,1 ; XLAT
    memory.load(0_u32, Bytes[0xD0, 0xE0, 0xD3, 0xE8, 0xD0, 0xC0, 0xD0, 0xF8, 0xD7])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x0081_u16

    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x02_u8)
    cpu.flags.carry.should be_true

    cpu.registers.ax = 0x0010_u16
    cpu.registers.cx = 4_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0001_u16)

    cpu.registers.ax = 0x0081_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x03_u8)
    cpu.flags.carry.should be_true

    cpu.registers.ax = 0x0080_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xC0_u8)
    cpu.flags.carry.should be_false

    cpu.registers.ds = 0x0010_u16
    cpu.registers.bx = 0x0020_u16
    cpu.registers.ax = 0x0003_u16
    memory.write_u8(0x0123_u32, 0x5A_u8)
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x5A_u8)
  end

  it "leaves a shift's flags unchanged for a zero count" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xD3, 0xE0])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x1234_u16
    cpu.flags.carry = true

    cpu.step(memory)
    cpu.registers.ax.should eq(0x1234_u16)
    cpu.flags.carry.should be_true
  end

  it "decodes the V30 immediate-count shift operand before its count" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xC0, 0xE0, 0x02, 0xC1, 0xE0, 0x02])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 1_u16

    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(4_u8)
    cpu.registers.ax = 1_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(4_u16)
  end

  it "executes the V30 F6/F7 arithmetic groups" do
    memory = Swanium::Core::FlatMemory.new
    # NOT AL ; NEG AL ; MUL CL ; DIV CL ; IMUL CX ; DIV CX
    memory.load(0_u32, Bytes[0xF6, 0xD0, 0xF6, 0xD8, 0xF6, 0xE1, 0xF6, 0xF1, 0xF7, 0xE9, 0xF7, 0xF1])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x000F_u16
    cpu.flags.carry = true

    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xF0_u8)
    cpu.flags.carry.should be_true
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x10_u8)
    cpu.flags.carry.should be_true

    cpu.registers.ax = 0x0010_u16
    cpu.registers.cx = 0x0010_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0100_u16)
    cpu.flags.overflow.should be_true

    cpu.registers.ax = 0x000A_u16
    cpu.registers.cx = 0x0003_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0103_u16)

    cpu.registers.ax = 0x0002_u16
    cpu.registers.cx = 0x0003_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0006_u16)
    cpu.registers.dx.should eq(0_u16)

    cpu.registers.dx = 0_u16
    cpu.registers.ax = 10_u16
    cpu.registers.cx = 3_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(3_u16)
    cpu.registers.dx.should eq(1_u16)
  end

  it "dispatches INT0 on divide by zero" do
    memory = Swanium::Core::FlatMemory.new
    memory.write_u16(0_u32, 0x3456_u16)
    memory.write_u16(2_u32, 0x1234_u16)
    memory.load(0x0200_u32, Bytes[0xF6, 0xF1])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0x0200_u16)
    cpu.registers.sp = 0x4000_u16
    cpu.registers.ax = 10_u16
    cpu.registers.cx = 0_u16

    cpu.step(memory)
    cpu.registers.cs.should eq(0x1234_u16)
    cpu.registers.ip.should eq(0x3456_u16)
    memory.read_u16(0x3FFA_u32).should eq(0x0202_u16)
  end

  it "executes V30 stack extensions and immediate IMUL" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0x60, 0x61, 0x68, 0x34, 0x12, 0x6A, 0xFF, 0x69, 0xC3, 0x03, 0x00, 0x6B, 0xC3, 0xFF])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0xFFFE_u16
    cpu.registers.ax = 0x1111_u16
    cpu.registers.di = 0x8888_u16

    cpu.step(memory)
    cpu.registers.sp.should eq(0xFFEE_u16)
    memory.read_u16(0xFFFC_u32).should eq(0x1111_u16)
    memory.read_u16(0xFFEE_u32).should eq(0x8888_u16)
    cpu.registers.ax = 0_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x1111_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)

    cpu.step(memory)
    memory.read_u16(0xFFFC_u32).should eq(0x1234_u16)
    cpu.step(memory)
    memory.read_u16(0xFFFA_u32).should eq(0xFFFF_u16)

    cpu.registers.bx = 5_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(15_u16)
    cpu.step(memory)
    cpu.registers.ax.should eq(0xFFFB_u16)
  end

  it "handles V30 far control transfers, software interrupts, and FF group" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0x9A, 0x20, 0x00, 0x34, 0x12])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0xFFFE_u16

    cpu.step(memory)
    cpu.registers.cs.should eq(0x1234_u16)
    cpu.registers.ip.should eq(0x0020_u16)
    memory.read_u16(0xFFFA_u32).should eq(5_u16)
    memory.read_u16(0xFFFC_u32).should eq(0_u16)

    memory.load(0x12360_u32, Bytes[0xCB])
    cpu.step(memory)
    cpu.registers.cs.should eq(0_u16)
    cpu.registers.ip.should eq(5_u16)

    memory.write_u16(0x000C_u32, 0x0040_u16)
    memory.write_u16(0x000E_u32, 0x2000_u16)
    memory.load(5_u32, Bytes[0xCC])
    cpu.step(memory)
    cpu.registers.cs.should eq(0x2000_u16)
    cpu.registers.ip.should eq(0x0040_u16)

    memory.load(0x20040_u32, Bytes[0xFF, 0xD0])
    cpu.registers.ax = 0x0080_u16
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0080_u16)
    memory.read_u16(cpu.registers.sp.to_u32).should eq(0x0042_u16)
  end

  it "executes V30 word strings, comparisons, and REP conditions" do
    memory = Swanium::Core::FlatMemory.new
    # MOVSW ; CMPSB ; STOSW ; LODSW ; SCASB ; REPNE SCASB
    memory.load(0_u32, Bytes[0xA5, 0xA6, 0xAB, 0xAD, 0xAE, 0xF2, 0xAE])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ds = 0_u16
    cpu.registers.es = 0_u16
    cpu.registers.si = 0x0100_u16
    cpu.registers.di = 0x0200_u16
    memory.write_u16(0x0100_u32, 0xBEEF_u16)

    cpu.step(memory)
    memory.read_u16(0x0200_u32).should eq(0xBEEF_u16)
    cpu.registers.si.should eq(0x0102_u16)
    cpu.registers.di.should eq(0x0202_u16)

    cpu.registers.si = 0x0110_u16
    cpu.registers.di = 0x0210_u16
    memory.write_u8(0x0110_u32, 0x33_u8)
    memory.write_u8(0x0210_u32, 0x33_u8)
    cpu.step(memory)
    cpu.flags.zero.should be_true

    cpu.registers.ax = 0xCAFE_u16
    cpu.registers.di = 0x0300_u16
    cpu.step(memory)
    memory.read_u16(0x0300_u32).should eq(0xCAFE_u16)
    cpu.registers.si = 0x0300_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0xCAFE_u16)

    cpu.registers.ax = 0x0042_u16
    cpu.registers.di = 0x0400_u16
    memory.write_u8(0x0400_u32, 0x42_u8)
    cpu.step(memory)
    cpu.flags.zero.should be_true

    cpu.registers.di = 0x0500_u16
    cpu.registers.cx = 5_u16
    cpu.registers.ax = 0x00FF_u16
    memory.load(0x0500_u32, Bytes[1, 2, 3, 0xFF, 5])
    cpu.step(memory)
    cpu.flags.zero.should be_true
    cpu.registers.cx.should eq(1_u16)
    cpu.registers.di.should eq(0x0504_u16)
  end

  it "executes BCD adjustment, AAM/AAD, SALC, and ENTER/LEAVE" do
    memory = Swanium::Core::FlatMemory.new
    # AAA ; AAS ; DAA ; DAS ; AAM 10 ; AAD 10 ; SALC ; ENTER 8,0 ; LEAVE
    memory.load(0_u32, Bytes[0x37, 0x3F, 0x27, 0x2F, 0xD4, 10, 0xD5, 10, 0xD6, 0xC8, 8, 0, 0, 0xC9])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x000F_u16

    cpu.step(memory)
    cpu.registers.ax.should eq(0x0105_u16)
    cpu.step(memory)
    cpu.registers.ax.should eq(0x000F_u16)

    cpu.registers.ax = 0x009A_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0_u8)
    cpu.flags.carry.should be_true
    cpu.registers.ax = 0x0000_u16
    cpu.flags.carry = true
    cpu.flags.auxiliary_carry = false
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xA0_u8)

    cpu.registers.ax = 30_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0300_u16)
    cpu.step(memory)
    cpu.registers.ax.should eq(30_u16)
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xFF_u8)

    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0x0100_u16
    cpu.registers.bp = 0xBEEF_u16
    cpu.step(memory)
    cpu.registers.bp.should eq(0x00FE_u16)
    cpu.registers.sp.should eq(0x00F6_u16)
    cpu.step(memory)
    cpu.registers.bp.should eq(0xBEEF_u16)
    cpu.registers.sp.should eq(0x0100_u16)
  end

  it "executes BOUND, V30 FE extensions, POP r/m, and string I/O" do
    memory = IoMemory.new
    memory.load(0_u32, Bytes[0x62, 0x06, 0x00, 0x02, 0xFE, 0xC0, 0xFE, 0xF0, 0x8F, 0xC3, 0x6C, 0x6E])
    memory.write_u16(0x0200_u32, 0_u16)
    memory.write_u16(0x0202_u32, 10_u16)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0xFFFE_u16
    cpu.registers.ax = 5_u16

    cpu.step(memory)
    cpu.registers.ip.should eq(4_u16)
    cpu.registers.ax = 0x007F_u16
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x80_u8)
    cpu.flags.carry.should be_true
    cpu.step(memory)
    memory.read_u16(0xFFFC_u32).should eq(0x0080_u16)
    cpu.step(memory)
    cpu.registers.bx.should eq(0x0080_u16)

    memory.set_port(0x10_u8, 0xAB_u8)
    cpu.registers.dx = 0x0010_u16
    cpu.registers.es = 0_u16
    cpu.registers.di = 0x0400_u16
    cpu.step(memory)
    memory.read_u8(0x0400_u32).should eq(0xAB_u8)
    cpu.registers.ds = 0_u16
    cpu.registers.si = 0x0400_u16
    cpu.step(memory)
    memory.writes.last.should eq({0x10_u8, 0xAB_u8})
  end

  it "loads V30 effective addresses and far pointers" do
    memory = Swanium::Core::FlatMemory.new
    # LEA AX,[BX+0x12] ; LEA CX,[BX+AX] ; LES BX,[0x80] ; LDS SI,[0x40]
    memory.load(0_u32, Bytes[0x8D, 0x47, 0x12, 0x8D, 0xC8, 0xC4, 0x1E, 0x80, 0, 0xC5, 0x36, 0x40, 0])
    memory.write_u16(0x0080_u32, 0x1234_u16)
    memory.write_u16(0x0082_u32, 0xABCD_u16)
    memory.write_u16(0x0040_u32, 0x5678_u16)
    memory.write_u16(0x0042_u32, 0x9ABC_u16)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.bx = 0x0100_u16

    cpu.step(memory)
    cpu.registers.ax.should eq(0x0112_u16)
    cpu.registers.ax = 0x1234_u16
    cpu.registers.bx = 0x5678_u16
    cpu.step(memory)
    cpu.registers.cx.should eq(0x68AC_u16)
    cpu.step(memory)
    cpu.registers.bx.should eq(0x1234_u16)
    cpu.registers.es.should eq(0xABCD_u16)
    cpu.step(memory)
    cpu.registers.si.should eq(0x5678_u16)
    cpu.registers.ds.should eq(0x9ABC_u16)
  end

  it "decodes group-one immediates after ModRM and applies moffs overrides" do
    memory = Swanium::Core::FlatMemory.new
    # ADD AX,0x1234 ; SUB BX,-1 ; ES:MOV AL,[0x10]
    memory.load(0_u32, Bytes[0x81, 0xC0, 0x34, 0x12, 0x83, 0xEB, 0xFF, 0x26, 0xA0, 0x10, 0])
    memory.write_u8(0x0110_u32, 0xAA_u8)
    memory.write_u8(0x0210_u32, 0xBB_u8)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ds = 0x0010_u16
    cpu.registers.es = 0x0020_u16

    cpu.step(memory)
    cpu.registers.ax.should eq(0x1234_u16)
    cpu.registers.bx = 1_u16
    cpu.step(memory)
    cpu.registers.bx.should eq(2_u16)
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xBB_u8)
  end

  it "handles V30 compatibility opcodes and prefixes without desynchronizing IP" do
    memory = Swanium::Core::FlatMemory.new
    # 0F ; LOCK NOP ; ESC [disp16] ; C0 /6 AL,2 ; INT1
    memory.load(0x0100_u32, Bytes[0x0F, 0xF0, 0x90, 0xD8, 0x06, 0x34, 0x12, 0xC0, 0xF0, 2, 0xF1])
    memory.write_u16(4_u32, 0x2000_u16)
    memory.write_u16(6_u32, 0x1000_u16)
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0x0100_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0x4000_u16
    cpu.registers.ax = 0x00FF_u16

    cpu.step(memory)
    cpu.registers.ip.should eq(0x0101_u16)
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0103_u16)
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0107_u16)
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0_u8)
    cpu.step(memory)
    cpu.registers.cs.should eq(0x1000_u16)
    cpu.registers.ip.should eq(0x2000_u16)
  end

  it "treats V30 FF group seven as a no-op" do
    memory = Swanium::Core::FlatMemory.new
    memory.load(0_u32, Bytes[0xFF, 0xF8])
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0_u16, 0_u16)
    cpu.registers.ax = 0x55AA_u16
    cpu.flags.carry = true

    cpu.step(memory)
    cpu.registers.ip.should eq(2_u16)
    cpu.registers.ax.should eq(0x55AA_u16)
    cpu.flags.carry.should be_true
    cpu.halted.should be_false
  end

  it "has a non-faulting representative encoding for every primary opcode" do
    256.times do |opcode|
      memory = Swanium::Core::FlatMemory.new
      memory.load(0_u32, Bytes[opcode.to_u8, 0, 0, 0, 0, 0, 0, 0])
      cpu = Swanium::Core::Cpu.new
      cpu.reset(0_u16, 0_u16)
      cpu.registers.ss = 0_u16
      cpu.registers.sp = 0xFFFE_u16
      cpu.step(memory)
      cpu.fault_opcode.should be_nil, "opcode 0x%02X faulted" % opcode
    end
  end

  # These cases correspond one-to-one to crates/core/src/cpu/tests/alu.rs in
  # the Rust implementation. Keep the names aligned to make parity reviews
  # mechanical rather than relying on broad multi-instruction smoke tests.
  it "matches Rust add_al_imm8_sets_carry_and_aux_carry" do
    cpu, memory = cpu_with(Bytes[0x04, 0x05])
    cpu.registers.ax = 0x00FE_u16

    cpu.step(memory).should eq(1_u32)
    cpu.registers.reg8(0_u8).should eq(0x03_u8)
    cpu.flags.carry.should be_true
    cpu.flags.auxiliary_carry.should be_true
    cpu.flags.overflow.should be_false
    cpu.flags.zero.should be_false
    cpu.flags.sign.should be_false
    cpu.flags.parity.should be_true
  end

  it "matches Rust add_al_imm8_signed_overflow" do
    cpu, memory = cpu_with(Bytes[0x04, 0x01])
    cpu.registers.ax = 0x007F_u16

    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x80_u8)
    cpu.flags.overflow.should be_true
    cpu.flags.sign.should be_true
    cpu.flags.carry.should be_false
  end

  it "matches Rust sub_al_imm8_borrows" do
    cpu, memory = cpu_with(Bytes[0x2C, 0x01])
    cpu.step(memory)

    cpu.registers.reg8(0_u8).should eq(0xFF_u8)
    cpu.flags.carry.should be_true
    cpu.flags.auxiliary_carry.should be_true
    cpu.flags.overflow.should be_false
    cpu.flags.sign.should be_true
  end

  it "matches Rust cmp_al_imm8_does_not_modify_register" do
    cpu, memory = cpu_with(Bytes[0x3C, 0x05])
    cpu.registers.ax = 0x0005_u16
    cpu.step(memory)

    cpu.registers.reg8(0_u8).should eq(0x05_u8)
    cpu.flags.zero.should be_true
    cpu.flags.carry.should be_false
  end

  it "matches Rust and_ax_imm16_clears_carry_and_overflow" do
    cpu, memory = cpu_with(Bytes[0x25, 0x0F, 0x0F])
    cpu.registers.ax = 0xFFFF_u16
    cpu.step(memory)

    cpu.registers.ax.should eq(0x0F0F_u16)
    cpu.flags.carry.should be_false
    cpu.flags.overflow.should be_false
  end

  it "matches Rust or_ax_imm16_sets_zero_flag_when_result_is_zero" do
    cpu, memory = cpu_with(Bytes[0x0D, 0x00, 0x00])
    cpu.step(memory)
    cpu.flags.zero.should be_true
  end

  it "matches Rust xor_ax_imm16_self_clears_register" do
    cpu, memory = cpu_with(Bytes[0x35, 0xFF, 0xFF])
    cpu.registers.ax = 0xFFFF_u16
    cpu.step(memory)

    cpu.registers.ax.should eq(0_u16)
    cpu.flags.zero.should be_true
  end

  it "matches Rust inc_ax_sets_overflow_at_signed_boundary_but_not_carry" do
    cpu, memory = cpu_with(Bytes[0x40])
    cpu.registers.ax = 0x7FFF_u16
    cpu.flags.carry = true
    cpu.step(memory).should eq(1_u32)

    cpu.registers.ax.should eq(0x8000_u16)
    cpu.flags.overflow.should be_true
    cpu.flags.auxiliary_carry.should be_true
    cpu.flags.carry.should be_true
  end

  it "matches Rust dec_ax_sets_overflow_at_signed_boundary_but_not_carry" do
    cpu, memory = cpu_with(Bytes[0x48])
    cpu.registers.ax = 0x8000_u16
    cpu.flags.carry = false
    cpu.step(memory)

    cpu.registers.ax.should eq(0x7FFF_u16)
    cpu.flags.overflow.should be_true
    cpu.flags.carry.should be_false
  end

  it "matches Rust add_rm16_r16_register_form" do
    cpu, memory = cpu_with(Bytes[0x01, 0xC3])
    cpu.registers.ax = 0x0010_u16
    cpu.registers.bx = 0x0005_u16
    cpu.step(memory).should eq(1_u32)

    cpu.registers.bx.should eq(0x0015_u16)
    cpu.registers.ax.should eq(0x0010_u16)
  end

  # One-to-one counterparts of crates/core/src/cpu/tests/mov_stack.rs.
  it "matches Rust mov_reg16_imm16" do
    cpu, memory = cpu_with(Bytes[0xB9, 0x34, 0x12])
    cpu.step(memory).should eq(1_u32)
    cpu.registers.cx.should eq(0x1234_u16)
  end

  it "matches Rust mov_reg8_imm8" do
    cpu, memory = cpu_with(Bytes[0xB4, 0x42])
    cpu.step(memory)
    cpu.registers.ax.should eq(0x4200_u16)
  end

  it "matches Rust mov_memory_bx_si_addressing" do
    cpu, memory = cpu_with(Bytes[0x88, 0x00])
    cpu.registers.ax = 0x00AB_u16
    cpu.registers.bx = 0x0010_u16
    cpu.registers.si = 0x0002_u16
    cpu.step(memory)
    memory.read_u8(0x0012_u32).should eq(0xAB_u8)
  end

  it "matches Rust mov_memory_direct_address_uses_ds" do
    cpu, memory = cpu_with(Bytes[0x88, 0x06, 0x00, 0x01])
    cpu.registers.ax = 0x007E_u16
    cpu.step(memory)
    memory.read_u8(0x0100_u32).should eq(0x7E_u8)
  end

  it "matches Rust mov_memory_bp_based_addressing_uses_ss_not_ds" do
    cpu, memory = cpu_with(Bytes[0x88, 0x02])
    cpu.registers.ax = 0x0099_u16
    cpu.registers.bp = 0x0004_u16
    cpu.registers.si = 0x0001_u16
    cpu.registers.ss = 0x0010_u16
    cpu.registers.ds = 0x0020_u16
    cpu.step(memory)

    memory.read_u8(0x0105_u32).should eq(0x99_u8)
    memory.read_u8(0x0205_u32).should eq(0_u8)
  end

  it "matches Rust push_pop_round_trip" do
    cpu, memory = cpu_with(Bytes[0x53])
    cpu.registers.bx = 0xBEEF_u16
    cpu.step(memory).should eq(1_u32)

    cpu.registers.sp.should eq(0xFFFC_u16)
    memory.read_u16(0xFFFC_u32).should eq(0xBEEF_u16)
  end

  it "matches Rust pop_restores_register_and_advances_stack_pointer" do
    cpu, memory = cpu_with(Bytes[0x59])
    cpu.registers.sp = 0xFFFC_u16
    memory.write_u16(0xFFFC_u32, 0xCAFE_u16)
    cpu.step(memory).should eq(1_u32)

    cpu.registers.cx.should eq(0xCAFE_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust push_then_pop_round_trips_value" do
    cpu, memory = cpu_with(Bytes[0x53, 0x59])
    cpu.registers.bx = 0xBEEF_u16
    cpu.step(memory)
    cpu.step(memory)

    cpu.registers.cx.should eq(0xBEEF_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  # One-to-one counterparts of crates/core/src/cpu/tests/ctrl_flow.rs.
  it "matches Rust reset_initializes_bootstrap_stack_pointer" do
    cpu = Swanium::Core::Cpu.new
    cpu.reset(0x1234_u16, 0x5678_u16)

    cpu.registers.cs.should eq(0x1234_u16)
    cpu.registers.ip.should eq(0x5678_u16)
    cpu.registers.sp.should eq(0x2000_u16)
  end

  it "matches Rust jmp_short_advances_ip_by_signed_offset" do
    cpu, memory = cpu_with(Bytes[0xEB, 0x04])
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0006_u16)
  end

  it "matches Rust jmp_short_negative_offset_wraps_backward" do
    cpu, memory = cpu_with(Bytes[0xEB, 0xFC])
    cpu.step(memory)
    cpu.registers.ip.should eq(0xFFFE_u16)
  end

  it "matches Rust jz_not_taken_when_zero_flag_clear" do
    cpu, memory = cpu_with(Bytes[0x74, 0x04])
    cpu.flags.zero = false
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0002_u16)
  end

  it "matches Rust jl_uses_sign_xor_overflow" do
    cpu, memory = cpu_with(Bytes[0x7C, 0x04])
    cpu.flags.sign = true
    cpu.flags.overflow = false
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0006_u16)
  end

  it "matches Rust hlt_sets_halted_and_subsequent_steps_are_idempotent" do
    cpu, memory = cpu_with(Bytes[0xF4])
    cpu.step(memory).should eq(1_u32)
    cpu.halted.should be_true
    cpu.registers.ip.should eq(1_u16)

    cpu.step(memory).should eq(1_u32)
    cpu.registers.ip.should eq(1_u16)
  end

  it "matches Rust flag_instructions_clc_stc_cli_sti_cld_std" do
    cpu, memory = cpu_with(Bytes[0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD])
    cpu.flags.carry = true
    cpu.flags.interrupt = true
    cpu.flags.direction = true

    cpu.step(memory)
    cpu.flags.carry.should be_false
    cpu.step(memory)
    cpu.flags.carry.should be_true
    cpu.step(memory)
    cpu.flags.interrupt.should be_false
    cpu.step(memory)
    cpu.flags.interrupt.should be_true
    cpu.step(memory)
    cpu.flags.direction.should be_false
    cpu.step(memory)
    cpu.flags.direction.should be_true
  end

  it "matches Rust jz_taken_when_zero_flag_set" do
    cpu, memory = cpu_with(Bytes[0x74, 0x03])
    cpu.flags.zero = true
    cpu.step(memory)
    cpu.registers.ip.should eq(5_u16)
  end

  it "matches Rust call_pushes_return_address_and_jumps" do
    cpu, memory = cpu_with(Bytes[0xE8, 0x10, 0x00])
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0013_u16)
    cpu.registers.sp.should eq(0xFFFC_u16)
    memory.read_u16(0xFFFC_u32).should eq(3_u16)
  end

  it "matches Rust ret_pops_return_address" do
    cpu, memory = cpu_with(Bytes[0xE8, 0x10, 0x00])
    memory.write_u8(0x0013_u32, 0xC3_u8)
    cpu.step(memory)
    cpu.step(memory)
    cpu.registers.ip.should eq(3_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust wscputest_one_byte_undefined_opcodes_are_nops" do
    [0x0F_u8, 0x63_u8, 0x64_u8, 0x65_u8, 0x66_u8, 0x67_u8].each do |opcode|
      cpu, memory = cpu_with(Bytes[opcode])
      cpu.registers.ax = 0x1234_u16
      cpu.flags.carry = true
      cpu.step(memory)
      cpu.registers.ip.should eq(1_u16)
      cpu.registers.ax.should eq(0x1234_u16)
      cpu.registers.cs.should eq(0_u16)
      cpu.flags.carry.should be_true
      cpu.fault_opcode.should be_nil
    end
  end

  it "matches Rust every_primary_opcode_executes_without_panicking" do
    256.times do |opcode|
      cpu, memory = cpu_with(Bytes[opcode.to_u8, 0, 0, 0, 0, 0, 0, 0])
      cpu.step(memory)
    end
  end

  it "matches Rust every_primary_opcode_has_a_non_faulting_representative_encoding" do
    256.times do |opcode|
      cpu, memory = cpu_with(Bytes[opcode.to_u8, 0, 0, 0, 0, 0, 0, 0])
      cpu.step(memory)
      cpu.fault_opcode.should be_nil, "opcode 0x%02X faulted" % opcode
    end
  end

  it "matches Rust handle_irq_dispatches_and_reports_acknowledge_cost" do
    cpu, memory = cpu_with(Bytes[0])
    memory.write_u16(0x80_u32, 0x5678_u16)
    memory.write_u16(0x82_u32, 0x1234_u16)
    cpu.reset(0x1000_u16, 0x2000_u16)
    cpu.registers.ss = 0_u16
    cpu.registers.sp = 0xFFFE_u16
    cpu.flags.interrupt = true
    cpu.service_interrupt(memory, 0x20_u8).should eq(10_u32)
    cpu.registers.cs.should eq(0x1234_u16)
    cpu.registers.ip.should eq(0x5678_u16)
    cpu.flags.interrupt.should be_false
    cpu.registers.sp.should eq(0xFFF8_u16)
  end

  it "matches Rust software_int_reports_full_cost_without_double_counting_acknowledge" do
    cpu, memory = cpu_with(Bytes[0xCD, 0x21])
    cpu.step(memory).should eq(10_u32)
  end
end
