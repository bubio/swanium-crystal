require "option_parser"
require "./swanium/core/machine"
require "./swanium/core/save_state"
require "./swanium/core/video_test_pattern"
require "./swanium/frontend/debugger"
require "./swanium/platform/sdl"
require "./swanium/platform/state_store"

module Swanium
  VERSION = "0.1.0"

  def self.run(arguments : Array(String)) : Nil
    sdl_smoke = false
    video_demo = false

    OptionParser.parse(arguments) do |parser|
      parser.banner = "Usage: swanium-crystal [options]"
      parser.on("--sdl-smoke", "Open an SDL2 window to verify the platform layer") { sdl_smoke = true }
      parser.on("--video-demo", "Run the 60 fps display and input test") { video_demo = true }
      parser.on("--version", "Print the version") do
        puts VERSION
        exit
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end

    if video_demo
      Platform::Sdl.video_demo
    elsif sdl_smoke
      Platform::Sdl.smoke_test
    else
      puts "Swanium Crystal #{VERSION}: core scaffold ready"
    end
  end
end

Swanium.run(ARGV)
