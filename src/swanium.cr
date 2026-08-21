require "option_parser"
require "./swanium/core/cartridge"
require "./swanium/core/machine"
require "./swanium/core/save_state"
require "./swanium/frontend/debugger"
require "./swanium/frontend/input_bindings"
require "./swanium/frontend/video_test_pattern"
require "./swanium/frontend/native_controls"
require "./swanium/platform/sdl"
require "./swanium/platform/state_store"

module Swanium
  VERSION = "1.0.0"

  def self.run(arguments : Array(String)) : Nil
    sdl_smoke = false
    video_smoke = false
    video_demo = false
    rom_path = nil.as(String?)
    rom_smoke_path = nil.as(String?)
    headless_frames = nil.as(Int32?)

    OptionParser.parse(arguments) do |parser|
      parser.banner = "Usage: swanium-crystal [options]"
      parser.on("--sdl-smoke", "Open an SDL2 window to verify the platform layer") { sdl_smoke = true }
      parser.on("--video-smoke", "Run a short self-contained video, input, and audio verification") { video_smoke = true }
      parser.on("--video-demo", "Run the 60 fps display and input test") { video_demo = true }
      parser.on("--rom PATH", "Run a local .ws or .wsc cartridge image") { |path| rom_path = path }
      parser.on("--rom-smoke PATH", "Run a short ROM, save-state, cartridge-save, video, input, and audio verification") { |path| rom_smoke_path = path }
      parser.on("--headless-frames COUNT", "Run a ROM without a window and fail on an unsupported CPU opcode") do |count|
        frames = count.to_i?
        raise OptionParser::InvalidOption.new("--headless-frames requires a non-negative integer") unless frames && frames >= 0
        headless_frames = frames
      end
      parser.on("--version", "Print the version") do
        puts VERSION
        exit
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end

    if headless_frames && !rom_path
      raise ArgumentError.new("--headless-frames requires --rom PATH")
    elsif rom_path && rom_smoke_path
      raise ArgumentError.new("--rom and --rom-smoke cannot be combined")
    elsif rom_path && (video_demo || video_smoke || sdl_smoke)
      raise ArgumentError.new("--rom cannot be combined with --video-demo, --video-smoke, or --sdl-smoke")
    elsif rom_smoke_path && (video_demo || video_smoke || sdl_smoke || headless_frames)
      raise ArgumentError.new("--rom-smoke cannot be combined with another run mode")
    elsif path = rom_smoke_path
      extension = File.extname(path).downcase
      raise ArgumentError.new("ROM must use the .ws or .wsc extension") unless extension.in?(".ws", ".wsc")
      cartridge = Core::CartridgeImage.from_bytes(File.read(path).to_slice)
      title = File.basename(path)
      Platform::Sdl.play(cartridge, title, 30_u32, verify_state_roundtrip: true)
      state_store = Platform::StateStore.default
      raise "ROM smoke did not persist save-state slot 0" unless state_store.state_exists?(cartridge.identity, 0)
      if cartridge.header.save_medium != Core::SaveMedium::None
        save_path = state_store.cartridge_save_path(title)
        unless File.exists?(save_path) && File.size(save_path) == cartridge.header.save_medium.size
          raise "ROM smoke did not persist cartridge save"
        end
      end
      puts "#{title}: ROM integration smoke passed"
    elsif path = rom_path
      if frames = headless_frames
        extension = File.extname(path).downcase
        raise ArgumentError.new("ROM must use the .ws or .wsc extension") unless extension.in?(".ws", ".wsc")
        rom = File.read(path).to_slice
        cartridge = Core::CartridgeImage.from_bytes(rom)
        title = File.basename(path)
        bus = Core::WonderSwanBus.from_cartridge(cartridge)
        machine = Core::Machine.new
        machine.cpu.reset(0xFFFF_u16, 0_u16)
        frames.times do |frame|
          machine.run_wonder_swan_frame(bus)
          if opcode = machine.cpu.fault_opcode
            raise "#{title}: unsupported CPU opcode 0x#{opcode.to_s(16).rjust(2, '0')} during frame #{frame + 1}"
          end
        end
        puts "#{title}: completed #{frames} headless frame(s)"
      else
        current_path = path
        loop do
          extension = File.extname(current_path).downcase
          raise ArgumentError.new("ROM must use the .ws or .wsc extension") unless extension.in?(".ws", ".wsc")
          Platform::StateStore.default.record_recent_rom(current_path)
          cartridge = Core::CartridgeImage.from_bytes(File.read(current_path).to_slice)
          title = File.basename(current_path)
          next_path = Platform::Sdl.play(cartridge, title)
          break unless next_path
          current_path = next_path
        end
      end
    elsif video_smoke
      Platform::Sdl.video_demo(30)
    elsif video_demo
      Platform::Sdl.video_demo
    elsif sdl_smoke
      Platform::Sdl.smoke_test
    else
      # A Finder-launched app has no command-line ROM path. Keep the main
      # window open and let its Open ROM menu action select a cartridge.
      if path = Platform::Sdl.launcher
        run(["--rom", path])
      end
    end
  end
end

begin
  Swanium.run(ARGV)
rescue ex : Exception
  STDERR.puts "swanium-crystal: #{ex.message}"
  if ENV["SWANIUM_BACKTRACE"]? == "1"
    ex.backtrace.try { |backtrace| STDERR.puts backtrace.join('\n') }
  end
  exit 1
end
