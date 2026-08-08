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
    bus.pending_interrupt_vector?.should eq(0x47_u8)
    # The interrupt is accepted at the following instruction boundary; the
    # scanline timer itself is already covered above by its pending vector.
    machine.step_wonder_swan(bus)
    machine.cpu.registers.ip.should eq(0x1236_u16)
  end

  it "runs a WonderSwan frame from deterministic emulated cycles" do
    bus = Swanium::Core::WonderSwanBus.new
    0x10000.times { |address| bus.write_u8(address.to_u32, 0x90_u8) }
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)

    machine.run_wonder_swan_frame(bus, Swanium::Core::WonderSwanKey::A)

    machine.scanline.should eq(0_u16)
    machine.cycles.should eq(Swanium::Core::Machine::CYCLES_PER_FRAME)
    bus.keys.should eq(Swanium::Core::WonderSwanKey::A)
    bus.read_io(0x02_u8).should eq(158_u8)
    machine.ppu.current_line.should eq(143_u8)
    machine.framebuffer_rgba.size.should eq(Swanium::Core::Ppu::PIXEL_COUNT * 4)
  end

  it "anchors successive frame deadlines to the master clock after an instruction overrun" do
    # TEST AL, 0 sets ZF once; JZ -2 then loops in five-cycle instructions.
    # A frame contains 40,704 cycles, which does not divide by five.
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_u8(0_u32, 0xA8_u8)
    bus.write_u8(1_u32, 0_u8)
    bus.write_u8(2_u32, 0x74_u8)
    bus.write_u8(3_u32, 0xFE_u8)
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)

    machine.run_wonder_swan_frame(bus)
    machine.cycles.should eq(40_706_u64)
    machine.run_wonder_swan_frame(bus)
    machine.cycles.should eq(81_411_u64)
    machine.run_wonder_swan_frame(bus)
    machine.cycles.should eq(122_116_u64)
  end

  it "delays a pending maskable interrupt for one instruction after STI" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_u8(0_u32, 0xFB_u8)
    bus.write_u8(1_u32, 0x90_u8)
    bus.write_io(0xB0_u8, 0x40_u8)
    bus.write_io(0xB2_u8, 0x80_u8)
    bus.request_interrupt(Swanium::Core::WonderSwanInterrupt::HBlankTimer)
    bus.write_u16(0x11C_u32, 0x7777_u16)
    bus.write_u16(0x11E_u32, 0_u16)
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)
    machine.cpu.registers.ss = 0_u16
    machine.cpu.registers.sp = 0x3FFE_u16

    machine.step_wonder_swan(bus)
    machine.cpu.registers.ip.should eq(1_u16)
    machine.step_wonder_swan(bus)
    machine.cpu.registers.ip.should eq(0x7777_u16)
    machine.cpu.flags.interrupt.should be_false
  end

  it "delivers INT 1 after an instruction when the V30 trap flag is set" do
    memory = Swanium::Core::FlatMemory.new
    memory.write_u8(0_u32, 0x90_u8) # NOP
    memory.write_u16(4_u32, 0x3456_u16)
    memory.write_u16(6_u32, 0x789A_u16)
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)
    machine.cpu.registers.ss = 0_u16
    machine.cpu.registers.sp = 0xFFFE_u16
    machine.cpu.flags.trap = true

    machine.step(memory).should eq(11_u32)

    machine.cpu.registers.ip.should eq(0x3456_u16)
    machine.cpu.registers.cs.should eq(0x789A_u16)
    machine.cpu.flags.trap.should be_false
    machine.cpu.flags.interrupt.should be_false
  end

  it "wakes HLT on a pending VBlank even while maskable interrupts are disabled" do
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_u8(0_u32, 0xF4_u8)
    bus.write_io(0xB2_u8, 0x40_u8)
    bus.on_vblank
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)

    machine.step_wonder_swan(bus)

    machine.cpu.halted.should be_false
    bus.interrupt_pending?(Swanium::Core::WonderSwanInterrupt::VBlank).should be_true
  end

  it "runs a headless program through an HBlank interrupt and back to HLT" do
    # STI ; HLT ; HLT
    # Handler at 0000:0100: MOV byte [0200],5A ; ACK HBlank ; IRET
    bus = Swanium::Core::WonderSwanBus.new
    bus.write_u8(0_u32, 0xFB_u8)
    bus.write_u8(1_u32, 0xF4_u8)
    bus.write_u8(2_u32, 0xF4_u8)
    bus.write_u8(0x100_u32, 0xC6_u8)
    bus.write_u8(0x101_u32, 0x06_u8)
    bus.write_u8(0x102_u32, 0x00_u8)
    bus.write_u8(0x103_u32, 0x02_u8)
    bus.write_u8(0x104_u32, 0x5A_u8)
    bus.write_u8(0x105_u32, 0xB0_u8)
    bus.write_u8(0x106_u32, 0x80_u8)
    bus.write_u8(0x107_u32, 0xE6_u8)
    bus.write_u8(0x108_u32, 0xB6_u8)
    bus.write_u8(0x109_u32, 0xCF_u8)
    bus.write_io(0xB0_u8, 0x40_u8)
    bus.write_io(0xB2_u8, 0x80_u8)
    bus.write_io(0xA4_u8, 1_u8)
    bus.write_io(0xA2_u8, 0x01_u8)
    bus.write_u16(0x11C_u32, 0x0100_u16)
    bus.write_u16(0x11E_u32, 0_u16)

    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0_u16, 0_u16)
    machine.cpu.registers.ss = 0_u16
    machine.cpu.registers.sp = 0x3FFE_u16

    machine.run_wonder_swan_frame(bus)

    bus.read_u8(0x0200_u32).should eq(0x5A_u8)
    machine.cpu.halted.should be_true
    machine.cpu.registers.cs.should eq(0_u16)
    machine.cpu.registers.ip.should eq(3_u16)
  end
end
