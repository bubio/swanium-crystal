require "option_parser"
require "./swanium/core/machine"
require "./swanium/platform/sdl"

module Swanium
  VERSION = "0.1.0"

  def self.run(arguments : Array(String)) : Nil
    sdl_smoke = false

    OptionParser.parse(arguments) do |parser|
      parser.banner = "Usage: swanium [options]"
      parser.on("--sdl-smoke", "Open an SDL2 window to verify the platform layer") { sdl_smoke = true }
      parser.on("--version", "Print the version") do
        puts VERSION
        exit
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end

    if sdl_smoke
      Platform::Sdl.smoke_test
    else
      puts "Swanium Crystal #{VERSION}: core scaffold ready"
    end
  end
end

Swanium.run(ARGV)
