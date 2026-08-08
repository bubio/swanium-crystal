require "../spec_helper"
require "../../src/swanium/core/cartridge"

describe Swanium::Core::CartridgeImage do
  it "decodes the footer model, orientation, mapper, and SRAM capacity" do
    rom = Bytes.new(0x20000, 0_u8)
    footer = rom.size - 16
    rom[footer] = 0xEA_u8
    rom[footer + 7] = 1_u8
    rom[footer + 8] = 0x44_u8
    rom[footer + 9] = 2_u8
    rom[footer + 11] = 2_u8
    rom[footer + 12] = 1_u8
    rom[footer + 13] = 1_u8

    cartridge = Swanium::Core::CartridgeImage.from_bytes(rom)
    cartridge.model.should eq(Swanium::Core::WonderSwanModel::Color)
    cartridge.header.save_medium.should eq(Swanium::Core::SaveMedium::Sram32KiB)
    cartridge.header.vertical.should be_true
    cartridge.header.mapper_2003.should be_true
    cartridge.header.game_id.should eq(0x44_u8)
  end

  it "rejects a file without a WonderSwan boot footer" do
    expect_raises(ArgumentError, /far-jump/) do
      Swanium::Core::CartridgeImage.from_bytes(Bytes.new(16, 0_u8))
    end
  end

  it "runs every cartridge on the fixed SwanCrystal hardware model" do
    rom = Bytes.new(0x10000, 0_u8)
    footer = rom.size - 16
    rom[footer] = 0xEA_u8

    cartridge = Swanium::Core::CartridgeImage.from_bytes(rom)
    bus = Swanium::Core::WonderSwanBus.from_cartridge(cartridge)

    cartridge.model.should eq(Swanium::Core::WonderSwanModel::Mono)
    bus.model.should eq(Swanium::Core::WonderSwanModel::Crystal)
  end

  it "persists cartridge EEPROM words through the hardware ports" do
    rom = Bytes.new(0x10000, 0_u8)
    footer = rom.size - 16
    rom[footer] = 0xEA_u8
    rom[footer + 11] = 0x10_u8
    bus = Swanium::Core::WonderSwanBus.from_cartridge(Swanium::Core::CartridgeImage.from_bytes(rom))

    bus.read_u8(0x10000_u32).should eq(0xFF_u8)
    bus.read_io(0xC8_u8).should eq(0x02_u8)
    command = (1_u16 << 8) | (3_u16 << 4) # EWEN, six address bits
    bus.write_io(0xC6_u8, (command & 0xFF_u16).to_u8)
    bus.write_io(0xC7_u8, (command >> 8).to_u8)
    bus.write_io(0xC8_u8, 0x40_u8)
    bus.write_io(0xC4_u8, 0xEF_u8)
    bus.write_io(0xC5_u8, 0xBE_u8)
    command = (1_u16 << 8) | (1_u16 << 6)
    bus.write_io(0xC6_u8, (command & 0xFF_u16).to_u8)
    bus.write_io(0xC7_u8, (command >> 8).to_u8)
    bus.write_io(0xC8_u8, 0x20_u8)
    command = (1_u16 << 8) | (2_u16 << 6)
    bus.write_io(0xC6_u8, (command & 0xFF_u16).to_u8)
    bus.write_io(0xC7_u8, (command >> 8).to_u8)
    bus.write_io(0xC8_u8, 0x10_u8)
    (bus.read_io(0xC4_u8).to_u16 | (bus.read_io(0xC5_u8).to_u16 << 8)).should eq(0xBEEF_u16)
    bus.save_ram[0].should eq(0xEF_u8)
    bus.save_ram[1].should eq(0xBE_u8)
  end
end
