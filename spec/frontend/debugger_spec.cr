require "../spec_helper"
require "../../src/swanium/frontend/debugger"

describe Swanium::Frontend::Debugger do
  it "pauses, single-steps, inspects memory, and toggles display layers" do
    debugger = Swanium::Frontend::Debugger.new
    machine = Swanium::Core::Machine.new
    bus = Swanium::Core::WonderSwanBus.new(model: Swanium::Core::WonderSwanModel::Crystal)
    bus.write_u8(0_u32, 0x90_u8)
    bus.write_io(0x00_u8, 0x07_u8)
    debugger.toggle_pause
    debugger.run_instruction?(machine, bus).should be_false
    debugger.request_step
    debugger.run_instruction?(machine, bus).should be_true
    machine.cpu.registers.ip.should eq(1_u16)

    debugger.move_memory(8)
    debugger.memory_address.should eq(8_u32)
    debugger.toggle_layer(bus, 1)
    bus.read_io(0x00_u8).should eq(0x05_u8)

    debugger.toggle_visible
    rgba = Bytes.new(Swanium::Core::Ppu::PIXEL_COUNT * 4, 0_u8)
    debugger.render(rgba, machine, bus)
    rgba.should_not eq(Bytes.new(rgba.size, 0_u8))
  end
end
