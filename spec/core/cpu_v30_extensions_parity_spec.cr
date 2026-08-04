require "../spec_helper"

private def extension_cpu(code : Bytes) : Tuple(Swanium::Core::Cpu, Swanium::Core::FlatMemory)
  memory = Swanium::Core::FlatMemory.new
  memory.load(0_u32, code)
  cpu = Swanium::Core::Cpu.new
  cpu.reset(0_u16, 0_u16)
  cpu.registers.ss = 0_u16
  cpu.registers.sp = 0xFFFE_u16
  {cpu, memory}
end

private def bound_cpu(index : UInt16, lower : UInt16, upper : UInt16) : Swanium::Core::Cpu
  cpu, memory = extension_cpu(Bytes[0x62, 0x06, 0x00, 0x02])
  memory.write_u16(0x0200_u32, lower)
  memory.write_u16(0x0202_u32, upper)
  memory.write_u16(0x0014_u32, 0x0050_u16)
  cpu.registers.ax = index
  cpu.step(memory)
  cpu
end

private def popa_cpu : Swanium::Core::Cpu
  cpu, memory = extension_cpu(Bytes[0x61])
  cpu.registers.sp = 0xFFEE_u16
  [0x00D1_u16, 0x0051_u16, 0x00B0_u16, 0x1111_u16, 0x00B3_u16, 0x00D2_u16, 0x00C1_u16, 0x00A0_u16].each_with_index do |value, index|
    memory.write_u16(0xFFEE_u32 + index.to_u32 * 2_u32, value)
  end
  cpu.step(memory)
  cpu
end

# One-to-one counterparts of the non-I/O portions of
# crates/core/src/cpu/tests/v30_extensions.rs.
describe "Rust V30 extension parity" do
  it "matches Rust pusha_decrements_sp_by_16" do
    cpu, memory = extension_cpu(Bytes[0x60])
    cpu.step(memory)
    cpu.registers.sp.should eq(0xFFEE_u16)
  end

  it "matches Rust pusha_pushes_ax_first" do
    cpu, memory = extension_cpu(Bytes[0x60])
    cpu.registers.ax = 0x1111_u16
    cpu.step(memory)
    memory.read_u16(0xFFFC_u32).should eq(0x1111_u16)
  end

  it "matches Rust pusha_pushes_di_last" do
    cpu, memory = extension_cpu(Bytes[0x60])
    cpu.registers.di = 0x8888_u16
    cpu.step(memory)
    memory.read_u16(0xFFEE_u32).should eq(0x8888_u16)
  end

  it "matches Rust pusha_pushes_original_sp" do
    cpu, memory = extension_cpu(Bytes[0x60])
    cpu.step(memory)
    memory.read_u16(0xFFF4_u32).should eq(0xFFFE_u16)
  end

  it "matches Rust popa_restores_ax" do
    cpu, memory = extension_cpu(Bytes[0x61])
    cpu.registers.sp = 0xFFEE_u16
    [0x00D1_u16, 0x0051_u16, 0x00B0_u16, 0x1111_u16, 0x00B3_u16, 0x00D2_u16, 0x00C1_u16, 0x00A0_u16].each_with_index do |value, index|
      memory.write_u16(0xFFEE_u32 + index.to_u32 * 2_u32, value)
    end
    cpu.step(memory)
    cpu.registers.ax.should eq(0x00A0_u16)
    cpu.registers.di.should eq(0x00D1_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)
    cpu.registers.sp.should_not eq(0x1111_u16)
  end

  it "matches Rust popa_restores_di" do
    popa_cpu.registers.di.should eq(0x00D1_u16)
  end

  it "matches Rust popa_increments_sp_by_16" do
    popa_cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust popa_discards_sp_slot" do
    popa_cpu.registers.sp.should_not eq(0x1111_u16)
  end

  it "matches Rust push_imm16_stores_value" do
    cpu, memory = extension_cpu(Bytes[0x68, 0x34, 0x12])
    cpu.step(memory)
    memory.read_u16(0xFFFC_u32).should eq(0x1234_u16)
  end

  it "matches Rust push_imm8_is_sign_extended" do
    cpu, memory = extension_cpu(Bytes[0x6A, 0xFF])
    cpu.step(memory)
    memory.read_u16(0xFFFC_u32).should eq(0xFFFF_u16)
  end

  it "matches Rust imul_reg_rm_imm16_computes_product" do
    cpu, memory = extension_cpu(Bytes[0x69, 0xC3, 0x03, 0x00])
    cpu.registers.bx = 5_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(15_u16)
  end

  it "matches Rust imul_reg_rm_imm8_sign_extends_immediate" do
    cpu, memory = extension_cpu(Bytes[0x6B, 0xC3, 0xFF])
    cpu.registers.bx = 5_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0xFFFB_u16)
  end

  it "matches Rust imul_imm_sets_overflow_when_truncated" do
    cpu, memory = extension_cpu(Bytes[0x6B, 0xC3, 0x04])
    cpu.registers.bx = 0x4000_u16
    cpu.step(memory)
    cpu.flags.overflow.should be_true
  end

  it "matches Rust shl_rm16_by_immediate_count" do
    cpu, memory = extension_cpu(Bytes[0xC1, 0xE0, 0x02])
    cpu.registers.ax = 1_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(4_u16)
  end

  it "matches Rust shl_rm8_by_immediate_count" do
    cpu, memory = extension_cpu(Bytes[0xC0, 0xE0, 0x02])
    cpu.registers.ax = 1_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(4_u8)
  end

  it "matches Rust wscputest_c0_c1_group_six_zero_destination_without_flags" do
    cpu, memory = extension_cpu(Bytes[0xC1, 0xF0, 0x03])
    cpu.registers.ax = 0x501A_u16
    cpu.flags.carry = true
    cpu.flags.zero = true
    cpu.step(memory)
    cpu.registers.ax.should eq(0_u16)
    cpu.flags.carry.should be_true
    cpu.flags.zero.should be_true

    cpu, memory = extension_cpu(Bytes[0xC0, 0xF0, 0x02])
    cpu.registers.ax = 0x101A_u16
    cpu.flags.carry = true
    cpu.flags.zero = true
    cpu.step(memory)
    cpu.registers.ax.should eq(0x1000_u16)
    cpu.flags.carry.should be_true
    cpu.flags.zero.should be_true
  end

  it "matches Rust pop_rm16_into_register" do
    cpu, memory = extension_cpu(Bytes[0x8F, 0xC0])
    cpu.registers.sp = 0xFFFC_u16
    memory.write_u16(0xFFFC_u32, 0xBEEF_u16)
    cpu.step(memory)
    cpu.registers.ax.should eq(0xBEEF_u16)
  end

  it "matches Rust pop_rm16_increments_sp" do
    cpu, memory = extension_cpu(Bytes[0x8F, 0xC0])
    cpu.registers.sp = 0xFFFC_u16
    cpu.step(memory)
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust wscputest_f6_f7_group_one_consumes_immediate_without_side_effects" do
    cpu, memory = extension_cpu(Bytes[0xF6, 0xC8, 0x90])
    cpu.registers.ax = 0xD01A_u16
    cpu.flags.zero = true
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.ax.should eq(0xD01A_u16)
    cpu.registers.ip.should eq(3_u16)
    cpu.flags.zero.should be_true
    cpu.flags.carry.should be_true

    cpu, memory = extension_cpu(Bytes[0xF7, 0xC8, 0x90, 0x90])
    cpu.registers.ax = 0xD01A_u16
    cpu.flags.zero = true
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.ax.should eq(0xD01A_u16)
    cpu.registers.ip.should eq(4_u16)
    cpu.flags.zero.should be_true
    cpu.flags.carry.should be_true
  end

  it "matches Rust wscputest_fe_extended_groups_match_ff_variants" do
    cpu, memory = extension_cpu(Bytes[0xFE, 0xF0])
    cpu.registers.ax = 0xFE5A_u16
    cpu.step(memory)
    cpu.registers.sp.should eq(0xFFFC_u16)
    memory.read_u16(0xFFFC_u32).should eq(0xFE5A_u16)
  end

  it "matches Rust wscputest_ff_group_seven_is_noop" do
    cpu, memory = extension_cpu(Bytes[0xFF, 0xF8])
    cpu.registers.ax = 0x55AA_u16
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.ax.should eq(0x55AA_u16)
    cpu.flags.carry.should be_true
    cpu.registers.ip.should eq(2_u16)
    cpu.fault_opcode.should be_nil
  end

  it "matches Rust bound_in_range_does_not_vector" do
    bound_cpu(5_u16, 0_u16, 10_u16).registers.ip.should eq(4_u16)
  end

  it "matches Rust bound_below_lower_raises_int5" do
    bound_cpu(0xFFFF_u16, 0_u16, 10_u16).registers.ip.should eq(0x0050_u16)
  end

  it "matches Rust bound_above_upper_raises_int5" do
    bound_cpu(20_u16, 0_u16, 10_u16).registers.ip.should eq(0x0050_u16)
  end
end
