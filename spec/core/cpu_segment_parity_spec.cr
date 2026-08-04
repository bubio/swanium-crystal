require "../spec_helper"

private def segment_cpu(code : Bytes) : Tuple(Swanium::Core::Cpu, Swanium::Core::FlatMemory)
  memory = Swanium::Core::FlatMemory.new
  memory.load(0_u32, code)
  cpu = Swanium::Core::Cpu.new
  cpu.reset(0_u16, 0_u16)
  cpu.registers.ss = 0_u16
  cpu.registers.sp = 0xFFFE_u16
  {cpu, memory}
end

# One-to-one counterparts of the segment, far-control, and frame portions of
# crates/core/src/cpu/tests/segment_string.rs.
describe "Rust V30 segment and frame parity" do
  it "matches Rust push_es_pushes_segment_value" do
    cpu, memory = segment_cpu(Bytes[0x06])
    cpu.registers.es = 0x1234_u16
    cpu.step(memory)
    cpu.registers.sp.should eq(0xFFFC_u16)
    memory.read_u16(0xFFFC_u32).should eq(0x1234_u16)
  end

  it "matches Rust pop_ds_restores_segment_register" do
    cpu, memory = segment_cpu(Bytes[0x1F])
    cpu.registers.sp = 0xFFFC_u16
    memory.write_u16(0xFFFC_u32, 0x5678_u16)
    cpu.step(memory)
    cpu.registers.ds.should eq(0x5678_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust mov_sreg_from_r16_updates_segment" do
    cpu, memory = segment_cpu(Bytes[0x8E, 0xD8])
    cpu.registers.ax = 0xABCD_u16
    cpu.step(memory)
    cpu.registers.ds.should eq(0xABCD_u16)
  end

  it "matches Rust mov_r16_from_sreg_reads_segment" do
    cpu, memory = segment_cpu(Bytes[0x8C, 0xC0])
    cpu.registers.es = 0x9900_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x9900_u16)
  end

  it "matches Rust es_override_redirects_memory_read_to_es_segment" do
    cpu, memory = segment_cpu(Bytes[0x26, 0xA1, 0x10, 0x00])
    cpu.registers.es = 0x1000_u16
    memory.write_u16(0x0010_u32, 0x1234_u16)
    memory.write_u16(0x10010_u32, 0x5678_u16)
    cpu.step(memory)
    cpu.registers.ax.should eq(0x5678_u16)
  end

  it "matches Rust cs_override_on_modrm_memory_access" do
    cpu, memory = segment_cpu(Bytes[0x2E, 0x8A, 0x07])
    cpu.registers.ds = 0x0100_u16
    cpu.registers.bx = 0x0050_u16
    memory.write_u8(0x0050_u32, 0xEE_u8)
    memory.write_u8(0x1050_u32, 0xFF_u8)
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0xEE_u8)
  end

  it "matches Rust mov_al_mem_direct_reads_from_ds" do
    cpu, memory = segment_cpu(Bytes[0xA0, 0x50, 0x00])
    memory.write_u8(0x0050_u32, 0x42_u8)
    cpu.step(memory)
    cpu.registers.reg8(0_u8).should eq(0x42_u8)
  end

  it "matches Rust mov_mem_direct_ax_writes_to_ds" do
    cpu, memory = segment_cpu(Bytes[0xA3, 0x60, 0x00])
    cpu.registers.ax = 0xBEEF_u16
    cpu.step(memory)
    memory.read_u16(0x0060_u32).should eq(0xBEEF_u16)
  end

  it "matches Rust lea_loads_effective_address_not_memory_value" do
    cpu, memory = segment_cpu(Bytes[0x8D, 0x18])
    cpu.registers.bx = 0x0100_u16
    cpu.registers.si = 0x0050_u16
    memory.write_u16(0x0150_u32, 0xDEAD_u16)
    cpu.step(memory)
    cpu.registers.bx.should eq(0x0150_u16)
  end

  it "matches Rust lea_with_displacement" do
    cpu, memory = segment_cpu(Bytes[0x8D, 0x47, 0x12])
    cpu.registers.bx = 0x0100_u16
    cpu.step(memory)
    cpu.registers.ax.should eq(0x0112_u16)
  end

  it "matches Rust wscputest_lea_register_mode_uses_extended_address_table" do
    cpu, memory = segment_cpu(Bytes[0x8D, 0xC8])
    cpu.registers.ax = 0x1234_u16
    cpu.registers.bx = 0x5678_u16
    cpu.step(memory)
    cpu.registers.cx.should eq(0x68AC_u16)

    cpu, memory = segment_cpu(Bytes[0x8D, 0xCA])
    cpu.registers.bp = 0x1234_u16
    cpu.registers.dx = 0x5678_u16
    cpu.step(memory)
    cpu.registers.cx.should eq(0x68AC_u16)
  end

  it "matches Rust les_loads_offset_and_es_from_memory" do
    cpu, memory = segment_cpu(Bytes[0xC4, 0x1E, 0x80, 0x00])
    memory.write_u16(0x0080_u32, 0x1234_u16)
    memory.write_u16(0x0082_u32, 0xABCD_u16)
    cpu.step(memory)
    cpu.registers.bx.should eq(0x1234_u16)
    cpu.registers.es.should eq(0xABCD_u16)
  end

  it "matches Rust wscputest_les_register_mode_uses_extended_address_table" do
    cpu, memory = segment_cpu(Bytes[0xC4, 0xD8])
    cpu.registers.ax = 0x0100_u16
    cpu.registers.bx = 0x0100_u16
    memory.write_u16(0x0200_u32, 0xF0AB_u16)
    memory.write_u16(0x0202_u32, 0x570D_u16)
    cpu.step(memory)
    cpu.registers.bx.should eq(0xF0AB_u16)
    cpu.registers.es.should eq(0x570D_u16)
  end

  it "matches Rust lds_loads_offset_and_ds_from_memory" do
    cpu, memory = segment_cpu(Bytes[0xC5, 0x36, 0x40, 0x00])
    memory.write_u16(0x0040_u32, 0x5678_u16)
    memory.write_u16(0x0042_u32, 0x9ABC_u16)
    cpu.step(memory)
    cpu.registers.si.should eq(0x5678_u16)
    cpu.registers.ds.should eq(0x9ABC_u16)
  end

  it "matches Rust wscputest_lds_register_mode_uses_extended_address_table" do
    cpu, memory = segment_cpu(Bytes[0xC5, 0xDE])
    cpu.registers.bp = 0x0100_u16
    cpu.registers.si = 0x0200_u16
    memory.write_u16(0x0300_u32, 0xF0AB_u16)
    memory.write_u16(0x0302_u32, 0x570D_u16)
    cpu.step(memory)
    cpu.registers.bx.should eq(0xF0AB_u16)
    cpu.registers.ds.should eq(0x570D_u16)
  end

  it "matches Rust enter_creates_stack_frame_and_leave_tears_it_down" do
    cpu, memory = segment_cpu(Bytes[0xC8, 0x08, 0x00, 0x00, 0xC9])
    cpu.registers.sp = 0x0100_u16
    cpu.registers.bp = 0xBEEF_u16
    cpu.step(memory)
    cpu.registers.bp.should eq(0x00FE_u16)
    cpu.registers.sp.should eq(0x00F6_u16)
    memory.read_u16(0x00FE_u32).should eq(0xBEEF_u16)
    cpu.step(memory)
    cpu.registers.sp.should eq(0x0100_u16)
    cpu.registers.bp.should eq(0xBEEF_u16)
  end

  it "matches Rust enter_with_nesting_pushes_frame_links" do
    cpu, memory = segment_cpu(Bytes[0xC8, 0x04, 0x00, 0x02])
    cpu.registers.sp = 0x0100_u16
    cpu.registers.bp = 0x0080_u16
    memory.write_u16(0x007E_u32, 0x1234_u16)
    cpu.step(memory)
    cpu.registers.bp.should eq(0x00FE_u16)
    cpu.registers.sp.should eq(0x00F6_u16)
    memory.read_u16(0x00FE_u32).should eq(0x0080_u16)
    memory.read_u16(0x00FC_u32).should eq(0x1234_u16)
    memory.read_u16(0x00FA_u32).should eq(0x00FE_u16)
  end

  it "matches Rust jmp_far_updates_cs_and_ip" do
    cpu, memory = segment_cpu(Bytes[0xEA, 0x10, 0x00, 0x34, 0x12])
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0010_u16)
    cpu.registers.cs.should eq(0x1234_u16)
  end

  it "matches Rust call_far_pushes_cs_and_ip_then_jumps" do
    cpu, memory = segment_cpu(Bytes[0x9A, 0x20, 0x00, 0x00, 0x00])
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0020_u16)
    cpu.registers.cs.should eq(0_u16)
    cpu.registers.sp.should eq(0xFFFA_u16)
    memory.read_u16(0xFFFA_u32).should eq(5_u16)
    memory.read_u16(0xFFFC_u32).should eq(0_u16)
  end

  it "matches Rust ret_far_pops_ip_then_cs" do
    cpu, memory = segment_cpu(Bytes[0xCB])
    cpu.registers.sp = 0xFFFA_u16
    memory.write_u16(0xFFFA_u32, 0x0030_u16)
    memory.write_u16(0xFFFC_u32, 0x1000_u16)
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0030_u16)
    cpu.registers.cs.should eq(0x1000_u16)
    cpu.registers.sp.should eq(0xFFFE_u16)
  end

  it "matches Rust ff_call_near_indirect_via_register" do
    cpu, memory = segment_cpu(Bytes[0xFF, 0xD0])
    cpu.registers.ax = 0x0050_u16
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0050_u16)
    memory.read_u16(0xFFFC_u32).should eq(2_u16)
  end

  it "matches Rust ff_jmp_near_indirect_via_register" do
    cpu, memory = segment_cpu(Bytes[0xFF, 0xE0])
    cpu.registers.ax = 0x0080_u16
    cpu.step(memory)
    cpu.registers.ip.should eq(0x0080_u16)
  end

  it "matches Rust ff_push_rm16_memory_form" do
    cpu, memory = segment_cpu(Bytes[0xFF, 0x36, 0x20, 0x00])
    memory.write_u16(0x0020_u32, 0xCAFE_u16)
    cpu.step(memory)
    cpu.registers.sp.should eq(0xFFFC_u16)
    memory.read_u16(0xFFFC_u32).should eq(0xCAFE_u16)
  end
end
