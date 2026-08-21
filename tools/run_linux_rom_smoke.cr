require "file_utils"

# Generates copyright-free horizontal and vertical WonderSwan cartridges and
# runs the real Linux frontend for a bounded number of frames. The footer asks
# for 8 KiB SRAM so the product path must round-trip both a save state and a
# cartridge save before it may report success.
binary = ARGV[0]? || raise ArgumentError.new("usage: run_linux_rom_smoke.cr BINARY")
root = File.join(Dir.tempdir, "swanium-linux-rom-smoke-#{Process.pid}")
state_root = File.join(root, "state")

begin
  Dir.mkdir_p(root)
  [{"horizontal.ws", false}, {"vertical.wsc", true}].each do |name, vertical|
    path = File.join(root, name)
    rom = Bytes.new(0x10000, 0x90_u8)
    footer = rom.size - 16
    rom[footer] = 0xEA_u8 # FAR JMP 0000:0000, the WonderSwan boot entry.
    rom[footer + 1] = 0_u8
    rom[footer + 2] = 0_u8
    rom[footer + 3] = 0_u8
    rom[footer + 4] = 0_u8
    rom[footer + 7] = vertical ? 1_u8 : 0_u8
    rom[footer + 8] = vertical ? 2_u8 : 1_u8
    rom[footer + 11] = 1_u8 # 8 KiB SRAM.
    rom[footer + 12] = vertical ? 1_u8 : 0_u8
    File.open(path, "wb") { |file| file.write(rom) }

    environment = {
      "XDG_STATE_HOME"  => state_root,
      "SDL_AUDIODRIVER" => ENV["SDL_AUDIODRIVER"]? || "dummy",
    }
    status = Process.run(binary, ["--rom-smoke", path], env: environment)
    raise "#{name} ROM integration smoke failed with exit status #{status.exit_code}" unless status.success?

    save = File.join(state_root, "swanium-crystal", "saves", "#{name}.sav")
    saved = File.read(save).to_slice
    unless saved.size == 8 * 1024 && saved[0] == 0x5A_u8
      raise "#{name} cartridge save did not preserve the state-round-trip marker"
    end
  end
ensure
  FileUtils.rm_rf(root)
end
