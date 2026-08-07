# CI-only end-to-end smoke test. The tiny program is generated locally rather
# than stored as a ROM file, so no third-party game or test program enters the
# repository. Its reset footer jumps to a stream of NOPs at 0000:0000.
binary = ARGV[0]? || raise ArgumentError.new("usage: run_headless_fixture.cr BINARY")
fixture_path = File.join(Dir.tempdir, "swanium-headless-fixture-#{Process.pid}.ws")

begin
  rom = Bytes.new(0x10000, 0x90_u8)
  footer = rom.size - 16
  rom[footer] = 0xEA_u8 # FAR JMP 0000:0000, the WonderSwan boot entry.
  rom[footer + 1] = 0_u8
  rom[footer + 2] = 0_u8
  rom[footer + 3] = 0_u8
  rom[footer + 4] = 0_u8

  File.open(fixture_path, "wb") { |file| file.write(rom) }
  status = Process.run(binary, ["--rom", fixture_path, "--headless-frames", "900"])
  raise "headless fixture failed with exit status #{status.exit_code}" unless status.success?
ensure
  File.delete(fixture_path) if File.exists?(fixture_path)
end
