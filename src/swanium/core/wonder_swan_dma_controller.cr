require "./apu"
require "./memory_bus"
require "./wonder_swan_hardware"

module Swanium
  module Core
    # Owns the Color/Crystal DMA register behavior and transfer state. The
    # controller accesses memory only through MemoryBus, leaving the platform
    # bus responsible for mapping and interrupt delivery.
    class WonderSwanDmaController
      private struct SdmaState
        property source : UInt32
        property counter : UInt32
        property source_shadow : UInt32
        property counter_shadow : UInt32
        property clock : UInt32
        property running : Bool

        def initialize(@source = 0_u32, @counter = 0_u32, @source_shadow = 0_u32,
                       @counter_shadow = 0_u32, @clock = 0_u32, @running = false)
        end
      end

      def initialize(@ports : Bytes, @model : WonderSwanModel)
        @sdma = SdmaState.new
        @pending_wait_cycles = 0_u32
      end

      # Returns true when a GDMA burst completed and the caller must raise the
      # DMA-complete interrupt.
      def write_io(port : UInt8, value : UInt8, memory : MemoryBus) : Bool
        case port
        when 0x40_u8, 0x44_u8, 0x46_u8
          @ports[port] = value & 0xFE_u8
        when 0x42_u8
          @ports[port] = value & 0x0F_u8
        when 0x4C_u8, 0x50_u8
          @ports[port] = value & 0x0F_u8
        when 0x43_u8, 0x49_u8, 0x4D_u8, 0x51_u8, 0x53_u8..0x5F_u8
          # Reserved / read-only holes.
        when 0x48_u8
          @ports[port] = value
          return execute_gdma(memory)
        else
          @ports[port] = value
        end
        false
      end

      def tick_sound(cycles : UInt32, apu : Apu, work_ram : Bytes, color_rendering_enabled : Bool,
                     memory : MemoryBus) : Nil
        unless @model.color? && sdma_enabled?
          @sdma.running = false
          @sdma.clock = 0_u32
          apu.tick(cycles, work_ram, @ports, @model.color?, color_rendering_enabled)
          return
        end

        cycles.times do
          tick_sdma_cycle(apu, memory)
          apu.tick(1_u32, work_ram, @ports, @model.color?, color_rendering_enabled)
        end
      end

      def consume_wait_cycles : UInt32
        cycles = @pending_wait_cycles
        @pending_wait_cycles = 0_u32
        cycles
      end

      def save_state(io : IO) : Nil
        io.write_bytes(@sdma.source, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.counter, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.source_shadow, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.counter_shadow, IO::ByteFormat::LittleEndian)
        io.write_bytes(@sdma.clock, IO::ByteFormat::LittleEndian)
        io.write_byte(@sdma.running ? 1_u8 : 0_u8)
      end

      def load_state(io : IO) : Nil
        @sdma = SdmaState.new(
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          io.read_bytes(UInt32, IO::ByteFormat::LittleEndian),
          (io.read_byte || raise IO::EOFError.new) != 0_u8
        )
      end

      def reset : Nil
        @sdma = SdmaState.new
        @pending_wait_cycles = 0_u32
      end

      private def execute_gdma(memory : MemoryBus) : Bool
        return false if (@ports[0x48] & 0x80_u8) == 0_u8

        source = read_port_u16(0x40_u8).to_u32 | ((@ports[0x42] & 0x0F_u8).to_u32 << 16)
        destination = read_port_u16(0x44_u8).to_u32
        remaining = read_port_u16(0x46_u8)
        if remaining == 0_u16
          @ports[0x48] &= 0x7F_u8
          return true
        end

        decrement = (@ports[0x48] & 0x40_u8) != 0_u8
        transferred = 0_u32
        while remaining > 0_u16
          break if gdma_source_blocked?(source)

          memory.write_u8(destination & 0xFFFF_u32, memory.read_u8(source))
          if decrement
            source &-= 1_u32
            destination &-= 1_u32
          else
            source &+= 1_u32
            destination &+= 1_u32
          end
          remaining &-= 1_u16
          transferred += 1_u32
        end

        write_port_u16(0x40_u8, (source & 0xFFFF_u32).to_u16)
        @ports[0x42] = ((source >> 16) & 0x0F_u32).to_u8
        write_port_u16(0x44_u8, (destination & 0xFFFF_u32).to_u16)
        write_port_u16(0x46_u8, remaining)
        @ports[0x48] &= 0x7F_u8
        @pending_wait_cycles += 5_u32 + transferred unless transferred == 0_u32
        true
      end

      private def sdma_enabled? : Bool
        (@ports[0x52] & 0x80_u8) != 0_u8
      end

      private def tick_sdma_cycle(apu : Apu, memory : MemoryBus) : Nil
        return unless start_sdma_if_needed

        @sdma.clock += 1_u32
        period = 128_u32 * sdma_rate
        return if @sdma.clock < period

        @sdma.clock -= period
        transfer_sdma_byte(apu, memory)
      end

      private def start_sdma_if_needed : Bool
        return true if @sdma.running

        counter = sdma_counter_from_ports
        if counter == 0_u32
          @ports[0x52] &= 0x7F_u8
          return false
        end

        @sdma.source = sdma_source_from_ports
        @sdma.counter = counter
        @sdma.source_shadow = @sdma.source
        @sdma.counter_shadow = counter
        @sdma.clock = 0_u32
        @sdma.running = true
        true
      end

      private def transfer_sdma_byte(apu : Apu, memory : MemoryBus) : Nil
        control = @ports[0x52]
        if (control & 0x04_u8) != 0_u8
          write_sdma_voice(0_u8, apu)
          return
        end

        write_sdma_voice(memory.read_u8(@sdma.source), apu)
        if (control & 0x40_u8) != 0_u8
          @sdma.source = (@sdma.source &- 1_u32) & ADDRESS_MASK
        else
          @sdma.source = (@sdma.source &+ 1_u32) & ADDRESS_MASK
        end
        @sdma.counter = (@sdma.counter &- 1_u32) & ADDRESS_MASK

        if @sdma.counter == 0_u32
          if (control & 0x08_u8) != 0_u8
            @sdma.source = @sdma.source_shadow
            @sdma.counter = @sdma.counter_shadow
          else
            @ports[0x52] &= 0x7F_u8
            @sdma.running = false
            @sdma.clock = 0_u32
          end
        end
        write_sdma_ports
      end

      private def write_sdma_voice(value : UInt8, apu : Apu) : Nil
        @ports[0x89] = value
        apu.write_voice(value) if (@ports[0x90] & 0x20_u8) != 0_u8
      end

      private def sdma_rate : UInt32
        case @ports[0x52] & 0x03_u8
        when 0_u8 then 6_u32
        when 1_u8 then 4_u32
        when 2_u8 then 2_u32
        else           1_u32
        end
      end

      private def sdma_source_from_ports : UInt32
        read_port_u16(0x4A_u8).to_u32 | ((@ports[0x4C] & 0x0F_u8).to_u32 << 16)
      end

      private def sdma_counter_from_ports : UInt32
        read_port_u16(0x4E_u8).to_u32 | ((@ports[0x50] & 0x0F_u8).to_u32 << 16)
      end

      private def write_sdma_ports : Nil
        write_port_u16(0x4A_u8, (@sdma.source & 0xFFFF_u32).to_u16)
        @ports[0x4C] = ((@sdma.source >> 16) & 0x0F_u32).to_u8
        write_port_u16(0x4E_u8, (@sdma.counter & 0xFFFF_u32).to_u16)
        @ports[0x50] = ((@sdma.counter >> 16) & 0x0F_u32).to_u8
      end

      private def gdma_source_blocked?(source : UInt32) : Bool
        (source >= 0x10000_u32 && source <= 0x1FFFF_u32) ||
          (source >= 0x80000_u32 && source <= 0x8FFFF_u32 && (@ports[0xA0] & 0x08_u8) != 0_u8)
      end

      private def read_port_u16(port : UInt8) : UInt16
        @ports[port].to_u16 | (@ports[port &+ 1_u8].to_u16 << 8)
      end

      private def write_port_u16(port : UInt8, value : UInt16) : Nil
        @ports[port] = (value & 0x00FF_u16).to_u8
        @ports[port &+ 1_u8] = (value >> 8).to_u8
      end
    end
  end
end
