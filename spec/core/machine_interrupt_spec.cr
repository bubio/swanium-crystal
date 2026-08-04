require "../spec_helper"

describe Swanium::Core::Machine do
  it "delivers an enabled timer interrupt at an instruction boundary" do
    memory = Swanium::Core::FlatMemory.new
    memory.write_u8(0_u32, 0x90_u8)
    memory.write_u16(0x20_u32, 0x0100_u16)
    memory.write_u16(0x22_u32, 0_u16)
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)
    machine.cpu.registers.ss = 0_u16
    machine.cpu.registers.sp = 0xFFFE_u16
    machine.cpu.flags.interrupt = true
    machine.interrupts.enabled_mask = 1_u8 << Swanium::Core::InterruptSource::Timer.value
    timer = Swanium::Core::Timer.new(1_u32, enabled: true)

    machine.step(memory, timer, 8_u8).should eq(11_u32)
    machine.cpu.registers.ip.should eq(0x0100_u16)
    machine.cycles.should eq(11_u64)
  end
end
