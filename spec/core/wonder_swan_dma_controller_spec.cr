require "../spec_helper"
require "../../src/swanium/core/wonder_swan_dma_controller"

describe Swanium::Core::WonderSwanDmaController do
  it "performs GDMA through the MemoryBus interface" do
    memory = Swanium::Core::FlatMemory.new
    ports = Bytes.new(0x100, 0_u8)
    dma = Swanium::Core::WonderSwanDmaController.new(ports, Swanium::Core::WonderSwanModel::Crystal)
    memory.write_u8(0x20000_u32, 0xA5_u8)
    memory.write_u8(0x20001_u32, 0x5A_u8)

    dma.write_io(0x40_u8, 0_u8, memory)
    dma.write_io(0x41_u8, 0_u8, memory)
    dma.write_io(0x42_u8, 0x02_u8, memory)
    dma.write_io(0x44_u8, 0x10_u8, memory)
    dma.write_io(0x46_u8, 2_u8, memory)

    dma.write_io(0x48_u8, 0x80_u8, memory).should be_true
    memory.read_u8(0x10_u32).should eq(0xA5_u8)
    memory.read_u8(0x11_u32).should eq(0x5A_u8)
    dma.consume_wait_cycles.should eq(7_u32)
  end
end
