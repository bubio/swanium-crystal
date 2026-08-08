require "./machine"

module Swanium
  module Core
    class SaveStateError < Exception
    end

    # Versioned, endian-stable whole-machine snapshots. File-system policy is
    # deliberately left to the frontend; the core only accepts and returns bytes.
    module SaveState
      MAGIC   = "SWCST001".to_slice
      VERSION = 5_u32

      def self.dump(machine : Machine, bus : WonderSwanBus) : Bytes
        io = IO::Memory.new
        io.write(MAGIC)
        io.write_bytes(VERSION, IO::ByteFormat::LittleEndian)
        write_cpu(io, machine.cpu)
        io.write_byte(machine.interrupts.enabled_mask)
        io.write_byte(machine.interrupts.pending_mask)
        io.write_bytes(machine.cycles, IO::ByteFormat::LittleEndian)
        io.write_bytes(machine.scanline, IO::ByteFormat::LittleEndian)
        io.write_bytes(machine.scanline_cycles, IO::ByteFormat::LittleEndian)
        io.write_byte(bus.model.value.to_u8)
        io.write_byte(bus.linear_offset)
        io.write_byte(bus.ram_bank)
        io.write_byte(bus.ram_bank_hi)
        io.write_byte(bus.rom_bank0)
        io.write_byte(bus.rom_bank0_hi)
        io.write_byte(bus.rom_bank1)
        io.write_byte(bus.rom_bank1_hi)
        io.write_bytes(bus.keys, IO::ByteFormat::LittleEndian)
        write_bytes(io, bus.work_ram)
        write_bytes(io, bus.save_ram)
        write_bytes(io, bus.ports)
        bus.save_rtc_state(io)
        bus.save_sdma_state(io)
        machine.ppu.save_state(io)
        machine.apu.save_state(io)
        io.to_slice.dup
      end

      def self.load(data : Bytes, machine : Machine, bus : WonderSwanBus) : Nil
        io = IO::Memory.new(data)
        magic = Bytes.new(MAGIC.size)
        io.read_fully(magic)
        raise SaveStateError.new("invalid save-state magic") unless magic == MAGIC
        version = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        raise SaveStateError.new("unsupported save-state version #{version}") unless version == VERSION
        cpu = read_cpu(io)
        interrupt_enabled = read_byte(io)
        interrupt_pending = read_byte(io)
        cycles = io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
        scanline = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
        scanline_cycles = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        model = read_byte(io)
        raise SaveStateError.new("save state is for a different hardware model") unless model == bus.model.value.to_u8
        linear_offset = read_byte(io)
        ram_bank = read_byte(io)
        ram_bank_hi = read_byte(io)
        rom_bank0 = read_byte(io)
        rom_bank0_hi = read_byte(io)
        rom_bank1 = read_byte(io)
        rom_bank1_hi = read_byte(io)
        keys = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
        work_ram = read_bytes(io, bus.work_ram.size)
        save_ram = read_bytes(io, bus.save_ram.size)
        ports = read_bytes(io, bus.ports.size)

        machine.cpu.restore(cpu)
        machine.interrupts.restore(interrupt_enabled, interrupt_pending)
        machine.restore_timing(cycles, scanline, scanline_cycles)
        bus.restore_state(work_ram, save_ram, ports, keys, linear_offset, ram_bank, ram_bank_hi,
          rom_bank0, rom_bank0_hi, rom_bank1, rom_bank1_hi)
        bus.load_rtc_state(io)
        bus.load_sdma_state(io)
        machine.ppu.load_state(io)
        machine.apu.load_state(io)
      rescue ex : IO::EOFError
        raise SaveStateError.new("truncated save state", cause: ex)
      end

      private def self.write_cpu(io : IO, cpu : Cpu) : Nil
        registers = cpu.registers
        {registers.ax, registers.cx, registers.dx, registers.bx,
         registers.sp, registers.bp, registers.si, registers.di,
         registers.cs, registers.ds, registers.ss, registers.es,
         registers.ip}.each { |value| io.write_bytes(value, IO::ByteFormat::LittleEndian) }
        io.write_bytes(cpu.flags.to_u16, IO::ByteFormat::LittleEndian)
        io.write_byte(cpu.halted ? 1_u8 : 0_u8)
        io.write_byte(cpu.snapshot.interrupt_inhibit)
      end

      private def self.read_cpu(io : IO) : CpuSnapshot
        words = StaticArray(UInt16, 13).new { io.read_bytes(UInt16, IO::ByteFormat::LittleEndian) }
        registers = Registers.new(
          ax: words[0], cx: words[1], dx: words[2], bx: words[3],
          sp: words[4], bp: words[5], si: words[6], di: words[7],
          cs: words[8], ds: words[9], ss: words[10], es: words[11], ip: words[12]
        )
        flags = Flags.from_u16(io.read_bytes(UInt16, IO::ByteFormat::LittleEndian))
        CpuSnapshot.new(registers, flags, read_byte(io) != 0_u8, read_byte(io))
      end

      private def self.write_bytes(io : IO, bytes : Bytes) : Nil
        io.write_bytes(bytes.size.to_u32, IO::ByteFormat::LittleEndian)
        io.write(bytes)
      end

      private def self.read_bytes(io : IO, expected_size : Int32) : Bytes
        size = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
        raise SaveStateError.new("save-state memory size does not match machine") unless size == expected_size.to_u32
        bytes = Bytes.new(expected_size)
        io.read_fully(bytes)
        bytes
      end

      private def self.read_byte(io : IO) : UInt8
        io.read_byte || raise IO::EOFError.new
      end
    end
  end
end
