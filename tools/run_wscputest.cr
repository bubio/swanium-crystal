require "../src/swanium/core/machine"

# Opt-in CPU ROM execution diagnostic. The ROM is supplied only by a local
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

instruction_limit = (ENV["WS_CPU_TEST_MAX_INSTRUCTIONS"]? || "2000000").to_i
unless instruction_limit > 0
  STDERR.puts "WS_CPU_TEST_MAX_INSTRUCTIONS must be positive"
  exit 64
end

image = File.read(path)
bus = Swanium::Core::WonderSwanBus.new(image.to_slice)
machine = Swanium::Core::Machine.new
machine.cpu.reset(0xFFFF_u16, 0x0000_u16)

instructions = 0
while instructions < instruction_limit && !machine.cpu.halted
  machine.step_wonder_swan(bus)
  instructions += 1
end

registers = machine.cpu.registers
fault = machine.cpu.fault_opcode
puts "instructions=#{instructions} cycles=#{machine.cycles} halted=#{machine.cpu.halted} fault=#{fault}"
puts "CS:IP=%04X:%04X AX=%04X BX=%04X CX=%04X DX=%04X SP=%04X" % {registers.cs, registers.ip, registers.ax, registers.bx, registers.cx, registers.dx, registers.sp}

if fault
  STDERR.puts "unsupported V30 opcode %02X" % fault
  exit 1
end

exit(machine.cpu.halted ? 0 : 2)
