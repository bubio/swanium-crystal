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
      @next_frame_cycle : UInt64

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
        # Frame requests are anchored to the machine clock, rather than to the
        # end of the previous request. CPU instructions are atomic and may
        # cross a deadline; anchoring prevents that bounded overrun from
        # accumulating into permanent video/audio drift.
        @next_frame_cycle = CYCLES_PER_FRAME
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

        # The V30 trap flag raises INT 1 after each executed instruction. It
        # is an architectural exception, so IF does not gate it and it takes
        # priority over a maskable device request at the same boundary.
        if @cpu.flags.trap
          cycles += @cpu.service_interrupt(bus, 1_u8)
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
        bus.consume_voice_writes { |sample| @apu.write_voice(sample) }
        # STI and SS loads inhibit exactly one *following instruction
        # boundary*, whether or not an IRQ happens to be pending there.  Do
        # not defer this decrement until an IRQ appears: that would consume
        # the delay after a long REP and lose its restart IP.
        maskable_allowed = @cpu.maskable_interrupt_allowed?
        trap_allowed = @cpu.trap_interrupt_allowed?
        if @cpu.flags.trap && trap_allowed
          cycles += @cpu.service_interrupt(bus, 1_u8)
        end
        if vector = bus.pending_interrupt_vector?
          if @cpu.flags.interrupt && maskable_allowed
            cycles += service_wonder_swan_interrupt(bus, vector)
          elsif @cpu.halted && bus.interrupt_pending?(WonderSwanInterrupt::VBlank)
            # A pending VBlank wakes HLT even when IF remains clear. The
            # request stays latched; only normal maskable delivery acknowledges
            # it once IF is enabled.
            @cpu.halted = false
          end
        end
        @cycles += cycles
        bus.tick_sound(cycles, @apu)
        bus.tick_rtc(cycles)
        advance_wonder_swan_display(bus, cycles)
        # A long REP can cross a scanline boundary and cause an IRQ only after
        # its instruction cycles have advanced display state.  Acknowledge it
        # here with the V30 restart IP, so IRET re-executes the REP prefix.
        if vector = bus.pending_interrupt_vector?
          if @cpu.flags.interrupt && maskable_allowed
            interrupt_cycles = service_wonder_swan_interrupt(bus, vector)
            cycles += interrupt_cycles
            @cycles += interrupt_cycles
            bus.tick_sound(interrupt_cycles, @apu)
            bus.tick_rtc(interrupt_cycles)
            advance_wonder_swan_display(bus, interrupt_cycles)
          end
        end
        cycles
      end

      # Advance to the next fixed 159-line WonderSwan frame deadline with one
      # stable input snapshot. This is deliberately driven from emulated cycles
      # rather than wall-clock time, so headless test ROMs observe the same
      # input and timer schedule as a frontend would. A CPU instruction is
      # indivisible and can cross a deadline; the following deadline remains
      # anchored to the master clock so that crossing does not accumulate drift.
      def run_wonder_swan_frame(bus : WonderSwanBus, keys : UInt16 = 0_u16) : Nil
        bus.set_keys(keys)
        bus.latch_sprites(@ppu)
        while @cycles < @next_frame_cycle
          step_wonder_swan(bus)
        end
        @next_frame_cycle += CYCLES_PER_FRAME
      end

      private def advance_wonder_swan_display(bus : WonderSwanBus, cycles : UInt32) : Nil
        @scanline_cycles += cycles
        while @scanline_cycles >= CYCLES_PER_SCANLINE
          @scanline_cycles -= CYCLES_PER_SCANLINE
          if @scanline < VISIBLE_SCANLINES
            bus.capture_next_frame_sprites(@ppu) if @scanline == VISIBLE_SCANLINES - 2
            bus.render_scanline(@ppu, @scanline.to_u8)
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

      private def service_wonder_swan_interrupt(bus : WonderSwanBus, vector : UInt8) : UInt32
        if saved_ip = @cpu.take_interrupt_return_override_ip
          @cpu.service_interrupt_at_ip(bus, vector, saved_ip)
        else
          @cpu.service_interrupt(bus, vector)
        end
      end

      def framebuffer_rgba : Bytes
        @ppu.framebuffer_rgba
      end

      def restore_timing(cycles : UInt64, scanline : UInt16, scanline_cycles : UInt32) : Nil
        @cycles = cycles
        @scanline = scanline
        @scanline_cycles = scanline_cycles
        @next_frame_cycle = next_frame_cycle_after(cycles)
      end

      def scanline_cycles : UInt32
        @scanline_cycles
      end

      private def next_frame_cycle_after(cycles : UInt64) : UInt64
        cycles - (cycles % CYCLES_PER_FRAME) + CYCLES_PER_FRAME
      end
    end
  end
end
