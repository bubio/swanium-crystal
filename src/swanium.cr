require "option_parser"
require "./swanium/core/cartridge"
require "./swanium/core/machine"
require "./swanium/core/save_state"
require "./swanium/frontend/debugger"
require "./swanium/frontend/video_test_pattern"
require "./swanium/platform/sdl"
require "./swanium/platform/state_store"

module Swanium
  VERSION = "0.1.0"

  def self.run(arguments : Array(String)) : Nil
    sdl_smoke = false
    video_demo = false
    rom_path = nil.as(String?)
    headless_frames = nil.as(Int32?)

    OptionParser.parse(arguments) do |parser|
      parser.banner = "Usage: swanium-crystal [options]"
      parser.on("--sdl-smoke", "Open an SDL2 window to verify the platform layer") { sdl_smoke = true }
      parser.on("--video-demo", "Run the 60 fps display and input test") { video_demo = true }
      parser.on("--rom PATH", "Run a local .ws or .wsc cartridge image") { |path| rom_path = path }
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
    elsif rom_path && (video_demo || sdl_smoke)
      raise ArgumentError.new("--rom cannot be combined with --video-demo or --sdl-smoke")
    elsif path = rom_path
      extension = File.extname(path).downcase
      raise ArgumentError.new("ROM must use the .ws or .wsc extension") unless extension.in?(".ws", ".wsc")
      rom = File.read(path).to_slice
      cartridge = Core::CartridgeImage.from_bytes(rom)
      title = File.basename(path)
      if frames = headless_frames
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
        Platform::Sdl.play(cartridge, title)
      end
    elsif video_demo
      Platform::Sdl.video_demo
    elsif sdl_smoke
      Platform::Sdl.smoke_test
    else
      puts "Swanium Crystal #{VERSION}: core scaffold ready"
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
