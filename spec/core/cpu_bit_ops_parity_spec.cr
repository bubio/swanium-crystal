require "../spec_helper"

private def bit_cpu(code : Bytes) : Tuple(Swanium::Core::Cpu, Swanium::Core::FlatMemory)
  memory = Swanium::Core::FlatMemory.new
  memory.load(0_u32, code)
  cpu = Swanium::Core::Cpu.new
  cpu.reset(0_u16, 0_u16)
  cpu.registers.ss = 0_u16
  cpu.registers.sp = 0xFFFE_u16
  {cpu, memory}
end

# One-to-one counterparts of crates/core/src/cpu/tests/bit_ops.rs.
describe "Rust V30 bit operation parity" do
  it "matches Rust shl_rm8_by_1_sets_carry_from_vacated_bit" do
    cpu, memory = bit_cpu(Bytes[0xD0, 0xE0])
    cpu.registers.ax = 0x0081_u16
    cpu.step(memory).should eq(1_u32)
    cpu.registers.reg8(0_u8).should eq(0x02_u8)
    cpu.flags.carry.should be_true
  end

  it "matches Rust shr_rm16_by_cl_shifts_multiple_bits" do
    cpu, memory = bit_cpu(Bytes[0xD3, 0xE8])
    cpu.registers.ax = 0x0010_u16
    cpu.registers.cx = 4_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(1_u16)
  end

  it "matches Rust shift_by_zero_leaves_flags_untouched" do
    cpu, memory = bit_cpu(Bytes[0xD3, 0xE0])
    cpu.registers.ax = 0x1234_u16
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.ax.should eq(0x1234_u16)
    cpu.flags.carry.should be_true
  end

  it "matches Rust rol_rm8_by_1_wraps_msb_into_carry_and_lsb" do
    cpu, memory = bit_cpu(Bytes[0xD0, 0xC0])
    cpu.registers.ax = 0x0081_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x03_u8)
    cpu.flags.carry.should be_true
  end

  it "matches Rust sar_preserves_sign_bit" do
    cpu, memory = bit_cpu(Bytes[0xD0, 0xF8])
    cpu.registers.ax = 0x0080_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xC0_u8)
    cpu.flags.carry.should be_false
  end

  it "matches Rust xchg_rm16_register_form_swaps_values" do
    cpu, memory = bit_cpu(Bytes[0x87, 0xC3])
    cpu.registers.ax = 0x1111_u16
    cpu.registers.bx = 0x2222_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x2222_u16)
    cpu.registers.bx.should eq(0x1111_u16)
  end

  it "matches Rust xchg_ax_with_register_short_form" do
    cpu, memory = bit_cpu(Bytes[0x91])
    cpu.registers.ax = 0xAAAA_u16
    cpu.registers.cx = 0xBBBB_u16
    cpu.step(memory).should eq(3_u32)
    cpu.registers.ax.should eq(0xBBBB_u16)
    cpu.registers.cx.should eq(0xAAAA_u16)
  end

  it "matches Rust test_al_imm8_does_not_modify_register" do
    cpu, memory = bit_cpu(Bytes[0xA8, 0x0F])
    cpu.registers.ax = 0x00F0_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xF0_u8)
    cpu.flags.zero.should be_true
  end

  it "matches Rust not_rm8_complements_bits_without_touching_flags" do
    cpu, memory = bit_cpu(Bytes[0xF6, 0xD0])
    cpu.registers.ax = 0x000F_u16
    cpu.flags.carry = true
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xF0_u8)
    cpu.flags.carry.should be_true
  end

  it "matches Rust neg_rm8_sets_carry_unless_operand_is_zero" do
    cpu, memory = bit_cpu(Bytes[0xF6, 0xD8])
    cpu.registers.ax = 1_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xFF_u8)
    cpu.flags.carry.should be_true
  end

  it "matches Rust mul_rm8_sets_carry_and_overflow_when_result_overflows_al" do
    cpu, memory = bit_cpu(Bytes[0xF6, 0xE1])
    cpu.registers.ax = 0x0010_u16
    cpu.registers.cx = 0x0010_u16
    cpu.step(memory).should eq(3_u32)
    cpu.registers.ax.should eq(0x0100_u16)
    cpu.flags.carry.should be_true
    cpu.flags.overflow.should be_true
  end

  it "matches Rust div_rm8_computes_quotient_and_remainder" do
    cpu, memory = bit_cpu(Bytes[0xF6, 0xF1])
    cpu.registers.ax = 10_u16
    cpu.registers.cx = 3_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0103_u16)
  end

  it "matches Rust div_rm8_by_zero_dispatches_int0" do
    cpu, memory = bit_cpu(Bytes[0xF6, 0xF1])
    cpu.registers.sp = 0x3FFE_u16
    cpu.registers.ax = 10_u16
    cpu.registers.cx = 0_u16
    cpu.step(memory)
    memory.read_u16(0x3FF8_u32).should eq(2_u16)
  end

  it "matches Rust loop_decrements_cx_and_branches_while_nonzero" do
    cpu, memory = bit_cpu(Bytes[0xE2, 0xFE])
    cpu.registers.cx = 2_u16
    cpu.step(memory).should eq(6_u32)
    cpu.registers.cx.should eq(1_u16)
    cpu.registers.ip.should eq(0_u16)
  end

  it "matches Rust loop_does_not_branch_when_cx_reaches_zero" do
    cpu, memory = bit_cpu(Bytes[0xE2, 0xFE])
    cpu.registers.cx = 1_u16
    cpu.step(memory).should eq(2_u32)
    cpu.registers.cx.should eq(0_u16)
    cpu.registers.ip.should eq(2_u16)
  end

  it "matches Rust jcxz_branches_when_cx_is_zero" do
    cpu, memory = bit_cpu(Bytes[0xE3, 0x04])
    cpu.step(memory)
    cpu.registers.ip.should eq(6_u16)
  end

  it "matches Rust cbw_sign_extends_negative_al_into_ah" do
    cpu, memory = bit_cpu(Bytes[0x98])
    cpu.registers.ax = 0x0080_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0xFF80_u16)
  end

  it "matches Rust cwd_sign_extends_negative_ax_into_dx" do
    cpu, memory = bit_cpu(Bytes[0x99])
    cpu.registers.ax = 0x8000_u16
    cpu.step(memory)
    cpu.registers.dx.should eq(0xFFFF_u16)
  end

  it "matches Rust lahf_then_sahf_round_trips_flag_byte" do
    cpu, memory = bit_cpu(Bytes[0x9F, 0x9E])
    cpu.flags.carry = true
    cpu.flags.zero = true
    cpu.step(memory)
    cpu.flags.carry = false
    cpu.flags.zero = false
    cpu.step(memory)
    cpu.flags.carry.should be_true
    cpu.flags.zero.should be_true
  end

  it "matches Rust pushf_then_popf_round_trips_flags" do
    cpu, memory = bit_cpu(Bytes[0x9C, 0x9D])
    cpu.flags.overflow = true
    cpu.flags.sign = true
    cpu.step(memory)
    cpu.flags.overflow = false
    cpu.flags.sign = false
    cpu.step(memory)
    cpu.flags.overflow.should be_true
    cpu.flags.sign.should be_true
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust xlat_reads_byte_at_ds_bx_plus_al" do
    cpu, memory = bit_cpu(Bytes[0xD7])
    memory.write_u8(0x0103_u32, 0x42_u8)
    cpu.registers.bx = 0x0100_u16
    cpu.registers.ax = 3_u16
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x42_u8)
  end
end
