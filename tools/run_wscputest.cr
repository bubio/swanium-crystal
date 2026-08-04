require "../src/swanium/core/machine"

# Opt-in WSCPUTest v0.7.1 verifier. The ROM is supplied only by a local
# environment variable and is never copied into the repository.
path = ENV["WS_CPU_TEST_ROM"]?
unless path && !path.empty?
  STDERR.puts "WS_CPU_TEST_ROM must name a local WSCPUTest image"
  exit 64
end

unless File.file?(path)
  STDERR.puts "WS_CPU_TEST_ROM does not name a readable file: #{path}"
  exit 66
end

frame_limit = (ENV["WS_CPU_TEST_MAX_FRAMES"]? || (75 * 180).to_s).to_i
unless frame_limit > 0
  STDERR.puts "WS_CPU_TEST_MAX_FRAMES must be positive"
  exit 64
end

image = File.read(path)
bus = Swanium::Core::WonderSwanBus.new(image.to_slice, model: Swanium::Core::WonderSwanModel::Color)
machine = Swanium::Core::Machine.new
machine.cpu.reset(0xFFFF_u16, 0x0000_u16)

def background_map_text(bus : Swanium::Core::WonderSwanBus) : String
  String.build do |text|
    32.times do |y|
      32.times do |x|
        byte = bus.read_u8(0x1000_u32 + y.to_u32 * 64_u32 + x.to_u32 * 2_u32)
        text << case byte
        when 0_u8             then ' '
        when 0x20_u8..0x7E_u8 then byte.chr
        else                       '.'
        end
      end
      text << '\n'
    end
  end
end

8.times { machine.run_wonder_swan_frame(bus) }
machine.run_wonder_swan_frame(bus, Swanium::Core::WonderSwanKey::A)
machine.run_wonder_swan_frame(bus)

latest_text = ""
frames = 0
while frames < frame_limit
  machine.run_wonder_swan_frame(bus)
  frames += 1
  latest_text = background_map_text(bus)
  break if latest_text.includes?("Failed!")
  break if latest_text.includes?("Ok!") && bus.read_u8(0x0136_u32) == 0_u8 && machine.cpu.halted
end

registers = machine.cpu.registers
fault = machine.cpu.fault_opcode
puts "frames=#{frames} cycles=#{machine.cycles} halted=#{machine.cpu.halted} fault=#{fault} testing=#{bus.read_u8(0x0136_u32)}"
puts "CS:IP=%04X:%04X AX=%04X BX=%04X CX=%04X DX=%04X SP=%04X" % {registers.cs, registers.ip, registers.ax, registers.bx, registers.cx, registers.dx, registers.sp}

if fault
  STDERR.puts "unsupported V30 opcode %02X" % fault
  exit 1
end

if latest_text.includes?("Failed!")
  STDERR.puts "WSCPUTest reported failure:\n#{latest_text}"
  exit 1
end

if latest_text.includes?("Ok!") && bus.read_u8(0x0136_u32) == 0_u8 && machine.cpu.halted
  puts "WSCPUTest passed"
  exit 0
end

STDERR.puts "WSCPUTest did not produce a completed Ok! result within #{frame_limit} frames:\n#{latest_text}"
exit 2
