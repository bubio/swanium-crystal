require "./hardware"

module Swanium
  module Core
    # Owns the WonderSwan interrupt registers, keypad matrix, and display
    # timers. The bus remains the address-map owner while this device models
    # the state transitions behind the CPU-visible interrupt ports.
    class WonderSwanInterruptController
      getter keys : UInt16

      def initialize(@ports : Bytes, @model : WonderSwanModel)
        @keys = 0_u16
      end

      def read_io?(port : UInt8) : UInt8?
        case port
        when 0xB0_u8
          @model == WonderSwanModel::Mono ? (@ports[port] & 0xF8_u8) | highest_pending_bit : @ports[port] & 0xF8_u8
        when 0xB4_u8
          refresh_serial_tx_irq
          cause = @ports[port]
          # Key, scanline and timer sources are edge-triggered and clear on
          # INT_CAUSE reads. Serial/cartridge/DMA remain level-latched.
          @ports[port] &= 0x0D_u8
          cause
        when 0xB5_u8
          scan_keys(@ports[port] & 0x70_u8)
        when 0xB6_u8
          0_u8
        when 0xB7_u8
          value = @ports[port] & 0x10_u8
          @ports[port] = value
          value
        else
          nil
        end
      end

      # Returns true when the port is owned by this device, including
      # read-only registers whose writes must be ignored.
      def write_io?(port : UInt8, value : UInt8) : Bool
        case port
        when 0xB0_u8
          @ports[port] = value & 0xF8_u8
        when 0xB2_u8
          @ports[port] = value
          refresh_serial_tx_irq
        when 0xB3_u8
          @ports[port] = value & 0xC4_u8
          refresh_serial_tx_irq
        when 0xB4_u8
          # INT_CAUSE is hardware-maintained.
        when 0xB5_u8
          @ports[port] = value & 0x70_u8
        when 0xB6_u8
          @ports[port] = value
          @ports[0xB4] &= ~value
        else
          return false
        end
        true
      end

      def request(source : WonderSwanInterrupt) : Nil
        @ports[0xB4] |= (1_u8 << source.value) & @ports[0xB2]
      end

      # The platform layer supplies a complete input snapshot. Only a newly
      # pressed key raises the edge-triggered KeyPress source.
      def set_keys(keys : UInt16) : Nil
        request(WonderSwanInterrupt::KeyPress) if (keys & ~@keys) != 0_u16
        @keys = keys
      end

      def restore_keys(keys : UInt16) : Nil
        @keys = keys
      end

      def pending_vector? : UInt8?
        7.downto(0) do |priority|
          return @ports[0xB0] &+ priority.to_u8 if @ports[0xB4].bit(priority) == 1
        end
        nil
      end

      # Called by the LCD scheduler at the beginning of HBlank.
      def on_hblank : Nil
        counter = read_u16(0xA8_u8)
        return if counter == 0_u16

        # The final count can still latch when its interrupt source is enabled,
        # even if the HBlank timer enable bit was cleared. This hardware quirk
        # is observable by WSHWTest and is relied upon by timer wait loops.
        enabled = (@ports[0xA2] & 0x01_u8) != 0_u8
        irq_enabled = (@ports[0xB2] & (1_u8 << WonderSwanInterrupt::HBlankTimer.value)) != 0_u8
        return unless enabled || (counter == 1_u16 && irq_enabled)

        if counter == 1_u16
          request(WonderSwanInterrupt::HBlankTimer)
          reload = (@ports[0xA2] & 0x02_u8) == 0_u8 ? 0_u16 : read_u16(0xA4_u8)
          write_u16(0xA8_u8, reload)
        else
          write_u16(0xA8_u8, counter - 1_u16)
        end
      end

      # Called by the LCD scheduler on the VBlank transition.
      def on_vblank : Nil
        request(WonderSwanInterrupt::VBlank)
        counter = read_u16(0xAA_u8)
        return if counter == 0_u16 || (@ports[0xA2] & 0x04_u8) == 0_u8

        if counter == 1_u16
          request(WonderSwanInterrupt::VBlankTimer)
          reload = (@ports[0xA2] & 0x08_u8) == 0_u8 ? 0_u16 : read_u16(0xA6_u8)
          write_u16(0xAA_u8, reload)
        else
          write_u16(0xAA_u8, counter - 1_u16)
        end
      end

      def set_current_scanline(line : UInt8) : Nil
        @ports[0x02] = line
        request(WonderSwanInterrupt::ScanlineMatch) if line == @ports[0x03]
      end

      private def read_u16(port : UInt8) : UInt16
        @ports[port].to_u16 | (@ports[port &+ 1_u8].to_u16 << 8)
      end

      private def write_u16(port : UInt8, value : UInt16) : Nil
        @ports[port] = (value & 0x00FF_u16).to_u8
        @ports[port &+ 1_u8] = (value >> 8).to_u8
      end

      private def scan_keys(selector : UInt8) : UInt8
        result = selector
        result |= (@keys & 0x000F_u16).to_u8 if (selector & 0x10_u8) != 0_u8
        result |= ((@keys >> 4) & 0x000F_u16).to_u8 if (selector & 0x20_u8) != 0_u8
        result |= ((@keys >> 8) & 0x000F_u16).to_u8 if (selector & 0x40_u8) != 0_u8
        result
      end

      private def highest_pending_bit : UInt8
        7.downto(0) do |priority|
          return priority.to_u8 if @ports[0xB4].bit(priority) == 1
        end
        0_u8
      end

      # Mono UART TX-ready is level-triggered: enabling both the UART and
      # IRQ-0 immediately asserts it, ACK cannot clear it while that level is
      # active. Color/Crystal hardware does not expose this Mono-only level.
      private def refresh_serial_tx_irq : Nil
        if @model == WonderSwanModel::Mono && (@ports[0xB2] & 0x01_u8) != 0_u8 && (@ports[0xB3] & 0x80_u8) != 0_u8
          @ports[0xB4] |= 0x01_u8
        end
      end
    end
  end
end
