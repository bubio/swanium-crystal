require "./cpu"
require "./apu"
require "./interrupt_controller"
require "./ppu"
require "./timer"
require "./wonder_swan_bus"

module Swanium
  module Core
    # Platform-independent owner for emulation state. Hardware components will be
    # added here without exposing SDL, filesystem, or wall-clock dependencies.
    class Machine
      CYCLES_PER_SCANLINE = 256_u32
      VISIBLE_SCANLINES   = 144_u16
      SCANLINES_PER_FRAME = 159_u16
      CYCLES_PER_FRAME    = CYCLES_PER_SCANLINE.to_u64 * SCANLINES_PER_FRAME

      getter cycles : UInt64
      getter apu : Apu
      getter cpu : Cpu
      getter interrupts : InterruptController
      getter ppu : Ppu
      getter scanline : UInt16

      def initialize
        @cycles = 0_u64
        @cpu = Cpu.new
        @apu = Apu.new
        @interrupts = InterruptController.new
        @ppu = Ppu.new
        @scanline_cycles = 0_u32
        @scanline = 0_u16
      end

      def run_cycles(cycles : UInt32) : Nil
        @cycles += cycles
      end

      # Run one instruction, advance an optional hardware timer by its V30
      # cycle cost, and deliver the highest-priority enabled request at the
      # following instruction boundary.
      def step(bus : MemoryBus, timer : Timer? = nil, timer_vector : UInt8 = 0_u8) : UInt32
        cycles = @cpu.step(bus)
        if timer && timer.advance(cycles) > 0_u32
          @interrupts.request(InterruptSource::Timer)
        end

        if @cpu.flags.interrupt && @cpu.maskable_interrupt_allowed?
          if source = @interrupts.next_pending?
            @interrupts.clear(source)
            cycles += @cpu.service_interrupt(bus, timer_vector)
          end
        end

        @cycles += cycles
        cycles
      end

      # Run one CPU instruction and acknowledge the WonderSwan bus's
      # highest-priority enabled request at the following instruction boundary.
      def step_wonder_swan(bus : WonderSwanBus) : UInt32
        cycles = @cpu.step(bus)
        bus.consume_voice_writes.each { |sample| @apu.write_voice(sample) }
        if @cpu.flags.interrupt && @cpu.maskable_interrupt_allowed?
          if vector = bus.pending_interrupt_vector?
            cycles += @cpu.service_interrupt(bus, vector)
          end
        end
        @cycles += cycles
        @apu.tick(cycles, bus.work_ram, bus.ports, bus.model.color?)
        advance_wonder_swan_display(bus, cycles)
        cycles
      end

      # Run a complete 159-line WonderSwan video frame with one stable input
      # snapshot. This is deliberately driven from emulated cycles rather than
      # wall-clock time, so headless test ROMs observe the same input and timer
      # schedule as a frontend would.
      def run_wonder_swan_frame(bus : WonderSwanBus, keys : UInt16 = 0_u16) : Nil
        bus.set_keys(keys)
        @ppu.latch_sprites_if_needed(bus.work_ram, bus.ports)
        target_cycles = @cycles + CYCLES_PER_FRAME
        while @cycles < target_cycles
          step_wonder_swan(bus)
        end
      end

      private def advance_wonder_swan_display(bus : WonderSwanBus, cycles : UInt32) : Nil
        @scanline_cycles += cycles
        while @scanline_cycles >= CYCLES_PER_SCANLINE
          @scanline_cycles -= CYCLES_PER_SCANLINE
          if @scanline < VISIBLE_SCANLINES
            @ppu.capture_next_frame_sprites(bus.work_ram, bus.ports) if @scanline == VISIBLE_SCANLINES - 2
            @ppu.render_scanline(@scanline.to_u8, bus.work_ram, bus.ports, bus.model.color?)
          end
          bus.set_current_scanline(@scanline.to_u8)
          bus.on_hblank
          bus.on_vblank if @scanline == VISIBLE_SCANLINES
          @scanline &+= 1_u16
          if @scanline == SCANLINES_PER_FRAME
            @scanline = 0_u16
            @ppu.promote_next_frame_sprites
          end
        end
      end

      def framebuffer_rgba : Bytes
        @ppu.framebuffer_rgba
      end

      def restore_timing(cycles : UInt64, scanline : UInt16, scanline_cycles : UInt32) : Nil
        @cycles = cycles
        @scanline = scanline
        @scanline_cycles = scanline_cycles
      end

      def scanline_cycles : UInt32
        @scanline_cycles
      end
    end
  end
end
