require "../spec_helper"
require "../../src/swanium/core/save_state"

describe Swanium::Core::SaveState do
  it "restores CPU, timing, memory, ports, PPU, and APU deterministically" do
    machine = Swanium::Core::Machine.new
    bus = Swanium::Core::WonderSwanBus.new(save_ram_size: 32, model: Swanium::Core::WonderSwanModel::Crystal)
    bus.work_ram[0] = 0x90_u8
    machine.cpu.registers.ax = 0x1234_u16
    machine.cpu.reset(0_u16, 0_u16)
    machine.step_wonder_swan(bus)
    machine.interrupts.enabled_mask = 0x24_u8
    machine.interrupts.request(Swanium::Core::InterruptSource::Timer)
    machine.apu.tick(128_u32, bus.work_ram, bus.ports)
    bus.write_u8(0x10000_u32, 0xA5_u8)
    saved = Swanium::Core::SaveState.dump(machine, bus)

    machine.cpu.registers.ax = 0xFFFF_u16
    bus.work_ram[7] = 0x77_u8
    bus.write_u8(0x10000_u32, 0_u8)
    Swanium::Core::SaveState.load(saved, machine, bus)

    machine.cpu.registers.ax.should eq(0_u16)
    machine.cpu.registers.ip.should eq(1_u16)
    machine.cycles.should eq(1_u64)
    machine.interrupts.enabled_mask.should eq(0x24_u8)
    machine.interrupts.pending_mask.should eq(0x04_u8)
    machine.apu.samples.should eq([0_i16, 0_i16])
    bus.work_ram[7].should eq(0_u8)
    bus.read_u8(0x10000_u32).should eq(0xA5_u8)
    Swanium::Core::SaveState.dump(machine, bus).should eq(saved)
  end

  it "rejects corrupt and incompatible state headers" do
    machine = Swanium::Core::Machine.new
    bus = Swanium::Core::WonderSwanBus.new
    expect_raises(Swanium::Core::SaveStateError, "invalid save-state magic") do
      Swanium::Core::SaveState.load(Bytes.new(12, 0_u8), machine, bus)
    end

    state = Swanium::Core::SaveState.dump(machine, bus)
    state[8] = 6_u8
    expect_raises(Swanium::Core::SaveStateError, "unsupported save-state version 6") do
      Swanium::Core::SaveState.load(state, machine, bus)
    end
  end

  it "leaves the running machine unchanged when a state is truncated after partial restore" do
    machine = Swanium::Core::Machine.new
    bus = Swanium::Core::WonderSwanBus.new
    machine.cpu.registers.ax = 0x1234_u16
    candidate = Swanium::Core::SaveState.dump(machine, bus)
    truncated = candidate[0, candidate.size - 1]

    machine.cpu.registers.ax = 0xBEEF_u16
    before = Swanium::Core::SaveState.dump(machine, bus)

    expect_raises(Swanium::Core::SaveStateError, "truncated save state") do
      Swanium::Core::SaveState.load(truncated, machine, bus)
    end

    Swanium::Core::SaveState.dump(machine, bus).should eq(before)
  end
end
