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

  it "uses the WonderSwan interrupt base and bus priority" do
    bus = Swanium::Core::WonderSwanBus.new
    512.times { |address| bus.write_u8(address.to_u32, 0x90_u8) }
    bus.write_io(0xB0_u8, 0x40_u8)
    bus.write_io(0xB2_u8, 0x80_u8)
    bus.request_interrupt(Swanium::Core::WonderSwanInterrupt::HBlankTimer)
    bus.write_u16(0x11C_u32, 0x2222_u16)
    bus.write_u16(0x11E_u32, 0x1111_u16)
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)
    machine.cpu.registers.ss = 0_u16
    machine.cpu.registers.sp = 0x3FFE_u16
    machine.cpu.flags.interrupt = true

    machine.step_wonder_swan(bus)
    machine.cpu.registers.ip.should eq(0x2222_u16)
    machine.cpu.registers.cs.should eq(0x1111_u16)
  end

  it "advances HBlank from deterministic 256-cycle scanlines" do
    bus = Swanium::Core::WonderSwanBus.new
    512.times { |address| bus.write_u8(address.to_u32, 0x90_u8) }
    bus.write_io(0xB0_u8, 0x40_u8)
    bus.write_io(0xB2_u8, 0x80_u8)
    bus.write_io(0xA4_u8, 1_u8)
    bus.write_io(0xA2_u8, 0x01_u8)
    bus.write_u16(0x11C_u32, 0x1234_u16)
    bus.write_u16(0x11E_u32, 0_u16)
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)
    machine.cpu.registers.ss = 0_u16
    machine.cpu.registers.sp = 0x3FFE_u16
    machine.cpu.flags.interrupt = true

    256.times { machine.step_wonder_swan(bus) }
    machine.scanline.should eq(1_u16)
    bus.read_io(0xB4_u8).should eq(0x80_u8)
    machine.step_wonder_swan(bus)
    machine.cpu.registers.ip.should eq(0x1234_u16)
  end
end
