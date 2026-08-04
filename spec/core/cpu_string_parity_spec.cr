require "../spec_helper"

private def string_cpu(code : Bytes) : Tuple(Swanium::Core::Cpu, Swanium::Core::FlatMemory)
  memory = Swanium::Core::FlatMemory.new
  memory.load(0_u32, code)
  cpu = Swanium::Core::Cpu.new
  cpu.reset(0_u16, 0_u16)
  cpu.registers.ss = 0_u16
  cpu.registers.sp = 0xFFFE_u16
  {cpu, memory}
end

# One-to-one counterparts of the string and BCD portions of
# crates/core/src/cpu/tests/segment_string.rs.
describe "Rust V30 string parity" do
  it "matches Rust movsb_copies_byte_from_ds_si_to_es_di" do
    cpu, memory = string_cpu(Bytes[0xA4])
    cpu.registers.si = 0x0100_u16
    cpu.registers.di = 0x0200_u16
    memory.write_u8(0x0100_u32, 0xAB_u8)
    cpu.step(memory)
    memory.read_u8(0x0200_u32).should eq(0xAB_u8)
    cpu.registers.si.should eq(0x0101_u16)
    cpu.registers.di.should eq(0x0201_u16)
  end

  it "matches Rust movsb_decrements_si_di_when_direction_flag_set" do
    cpu, memory = string_cpu(Bytes[0xA4])
    cpu.registers.si = 0x0100_u16
    cpu.registers.di = 0x0200_u16
    cpu.flags.direction = true
    memory.write_u8(0x0100_u32, 0x55_u8)
    cpu.step(memory)
    memory.read_u8(0x0200_u32).should eq(0x55_u8)
    cpu.registers.si.should eq(0x00FF_u16)
    cpu.registers.di.should eq(0x01FF_u16)
  end

  it "matches Rust stosb_writes_al_to_es_di" do
    cpu, memory = string_cpu(Bytes[0xAA])
    cpu.registers.di = 0x0300_u16
    cpu.registers.ax = 0x00CC_u16
    cpu.step(memory)
    memory.read_u8(0x0300_u32).should eq(0xCC_u8)
    cpu.registers.di.should eq(0x0301_u16)
  end

  it "matches Rust lodsb_loads_byte_from_ds_si_into_al" do
    cpu, memory = string_cpu(Bytes[0xAC])
    cpu.registers.si = 0x0050_u16
    memory.write_u8(0x0050_u32, 0x77_u8)
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x77_u8)
    cpu.registers.si.should eq(0x0051_u16)
  end

  it "matches Rust scasb_compares_al_with_es_di_and_sets_zero_on_match" do
    cpu, memory = string_cpu(Bytes[0xAE])
    cpu.registers.di = 0x0400_u16
    cpu.registers.ax = 0x0042_u16
    memory.write_u8(0x0400_u32, 0x42_u8)
    cpu.step(memory)
    cpu.flags.zero.should be_true
    cpu.registers.di.should eq(0x0401_u16)
  end

  it "matches Rust cmpsb_sets_zero_when_bytes_are_equal" do
    cpu, memory = string_cpu(Bytes[0xA6])
    cpu.registers.si = 0x0100_u16
    cpu.registers.di = 0x0200_u16
    memory.write_u8(0x0100_u32, 0x33_u8)
    memory.write_u8(0x0200_u32, 0x33_u8)
    cpu.step(memory)
    cpu.flags.zero.should be_true
  end

  it "matches Rust rep_stosb_fills_region_with_al" do
    cpu, memory = string_cpu(Bytes[0xF3, 0xAA])
    cpu.registers.di = 0x0500_u16
    cpu.registers.cx = 4_u16
    cpu.registers.ax = 0x00FF_u16
    cpu.step(memory)
    cpu.registers.cx.should eq(0_u16)
    cpu.registers.di.should eq(0x0504_u16)
    4.times { |index| memory.read_u8(0x0500_u32 + index.to_u32).should eq(0xFF_u8) }
  end

  it "matches Rust rep_movsb_copies_cx_bytes" do
    cpu, memory = string_cpu(Bytes[0xF3, 0xA4])
    cpu.registers.si = 0x0100_u16
    cpu.registers.di = 0x0200_u16
    cpu.registers.cx = 3_u16
    memory.write_u8(0x0100_u32, 1_u8)
    memory.write_u8(0x0101_u32, 2_u8)
    memory.write_u8(0x0102_u32, 3_u8)
    cpu.step(memory)
    cpu.registers.cx.should eq(0_u16)
    memory.read_u8(0x0200_u32).should eq(1_u8)
    memory.read_u8(0x0201_u32).should eq(2_u8)
    memory.read_u8(0x0202_u32).should eq(3_u8)
  end

  it "matches Rust repne_scasb_stops_at_matching_byte" do
    cpu, memory = string_cpu(Bytes[0xF2, 0xAE])
    cpu.registers.di = 0x0300_u16
    cpu.registers.cx = 5_u16
    cpu.registers.ax = 0x00FF_u16
    Bytes[1, 2, 3, 0xFF, 5].each_with_index { |byte, index| memory.write_u8(0x0300_u32 + index.to_u32, byte) }
    cpu.step(memory)
    cpu.flags.zero.should be_true
    cpu.registers.cx.should eq(1_u16)
    cpu.registers.di.should eq(0x0304_u16)
  end

  it "matches Rust rep_with_cx_zero_is_nop" do
    cpu, memory = string_cpu(Bytes[0xF3, 0xAA])
    cpu.registers.di = 0x0600_u16
    cpu.registers.ax = 0x00EE_u16
    cpu.step(memory)
    memory.read_u8(0x0600_u32).should eq(0_u8)
    cpu.registers.di.should eq(0x0600_u16)
  end

  it "matches Rust aaa_adjusts_after_bcd_add" do
    cpu, memory = string_cpu(Bytes[0x37])
    cpu.registers.ax = 0x000F_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x05_u8)
    cpu.registers.reg8(4_u8).should eq(1_u8)
    cpu.flags.carry.should be_true
    cpu.flags.auxiliary_carry.should be_true
  end

  it "matches Rust aam_divides_al_by_base" do
    cpu, memory = string_cpu(Bytes[0xD4, 0x0A])
    cpu.registers.ax = 0x001E_u16
    cpu.step(memory)
    cpu.registers.reg8(4_u8).should eq(3_u8)
    cpu.registers.reg8(0_u8).should eq(0_u8)
    cpu.flags.zero.should be_true
  end

  it "matches Rust aad_combines_ah_al_before_division" do
    cpu, memory = string_cpu(Bytes[0xD5, 0x0A])
    cpu.registers.ax = 0x0305_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(35_u16)
    cpu.registers.reg8(4_u8).should eq(0_u8)
  end
end
