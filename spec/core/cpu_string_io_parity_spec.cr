require "../spec_helper"

class StringIoMemory < Swanium::Core::FlatMemory
  getter last_out : Tuple(UInt8, UInt8)?

  def initialize
    super
    @ports = Bytes.new(0x100, 0_u8)
    @last_out = nil
  end

  def set_port(port : UInt8, value : UInt8) : Nil
    @ports[port] = value
  end

  def read_io(port : UInt8) : UInt8
    @ports[port]
  end

  def write_io(port : UInt8, value : UInt8) : Nil
    @ports[port] = value
    @last_out = {port, value}
  end
end

private def string_io_cpu(code : Bytes) : Tuple(Swanium::Core::Cpu, StringIoMemory)
  memory = StringIoMemory.new
  memory.load(0_u32, code)
  cpu = Swanium::Core::Cpu.new
  cpu.reset(0_u16, 0_u16)
  cpu.registers.ss = 0_u16
  cpu.registers.sp = 0xFFFE_u16
  {cpu, memory}
end

# One-to-one counterparts of the INS/OUTS cases in
# crates/core/src/cpu/tests/v30_extensions.rs.
describe "Rust V30 string I/O parity" do
  it "matches Rust insb_reads_port_into_memory" do
    cpu, memory = string_io_cpu(Bytes[0x6C])
    cpu.registers.dx = 0x0010_u16
    cpu.registers.di = 0x0500_u16
    memory.set_port(0x10_u8, 0xAB_u8)
    cpu.step(memory)
    memory.read_u8(0x0500_u32).should eq(0xAB_u8)
  end

  it "matches Rust insb_increments_di" do
    cpu, memory = string_io_cpu(Bytes[0x6C])
    cpu.registers.di = 0x0500_u16
    cpu.step(memory)
    cpu.registers.di.should eq(0x0501_u16)
  end

  it "matches Rust insw_reads_word_from_two_ports" do
    cpu, memory = string_io_cpu(Bytes[0x6D])
    cpu.registers.dx = 0x0010_u16
    cpu.registers.di = 0x0500_u16
    memory.set_port(0x10_u8, 0xCD_u8)
    memory.set_port(0x11_u8, 0xAB_u8)
    cpu.step(memory)
    memory.read_u16(0x0500_u32).should eq(0xABCD_u16)
  end

  it "matches Rust outsb_writes_memory_to_port" do
    cpu, memory = string_io_cpu(Bytes[0x6E])
    cpu.registers.dx = 0x0020_u16
    cpu.registers.si = 0x0400_u16
    memory.write_u8(0x0400_u32, 0xCD_u8)
    cpu.step(memory)
    memory.last_out.should eq({0x20_u8, 0xCD_u8})
  end

  it "matches Rust outsb_increments_si" do
    cpu, memory = string_io_cpu(Bytes[0x6E])
    cpu.registers.si = 0x0400_u16
    cpu.step(memory)
    cpu.registers.si.should eq(0x0401_u16)
  end

  it "matches Rust outsw_writes_high_byte_to_next_port" do
    cpu, memory = string_io_cpu(Bytes[0x6F])
    cpu.registers.dx = 0x0020_u16
    cpu.registers.si = 0x0400_u16
    memory.write_u16(0x0400_u32, 0xABCD_u16)
    cpu.step(memory)
    memory.last_out.should eq({0x21_u8, 0xAB_u8})
  end

  it "matches Rust outsb_honours_direction_flag" do
    cpu, memory = string_io_cpu(Bytes[0x6E])
    cpu.registers.si = 0x0400_u16
    cpu.flags.direction = true
    cpu.step(memory)
    cpu.registers.si.should eq(0x03FF_u16)
  end

  it "matches Rust rep_outsb_consumes_cx" do
    cpu, memory = string_io_cpu(Bytes[0xF3, 0x6E])
    cpu.registers.cx = 3_u16
    cpu.registers.dx = 0x0020_u16
    cpu.registers.si = 0x0400_u16
    cpu.step(memory)
    cpu.registers.cx.should eq(0_u16)
  end

  it "matches Rust rep_insb_advances_di_per_byte" do
    cpu, memory = string_io_cpu(Bytes[0xF3, 0x6C])
    cpu.registers.cx = 4_u16
    cpu.registers.di = 0x0500_u16
    cpu.step(memory)
    cpu.registers.di.should eq(0x0504_u16)
  end
end
