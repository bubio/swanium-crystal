module Swanium
  module Core
    # CPU-visible interrupt sources. The numeric values are bit positions in
    # the controller's enable and pending masks.
    enum InterruptSource : UInt8
      VBlank    = 0
      HBlank    = 1
      Timer     = 2
      Serial    = 3
      Key       = 4
      Cartridge = 5
    end

    # Deterministic edge-latched interrupt controller. The future I/O map only
    # needs to connect its registers to these operations.
    class InterruptController
      property enabled_mask : UInt8
      getter pending_mask : UInt8

      def initialize
        @enabled_mask = 0_u8
        @pending_mask = 0_u8
      end

      def request(source : InterruptSource) : Nil
        @pending_mask |= bit(source)
      end

      def clear(source : InterruptSource) : Nil
        @pending_mask &= ~bit(source)
      end

      def next_pending? : InterruptSource?
        active = @pending_mask & @enabled_mask
        InterruptSource.each do |source|
          return source if (active & bit(source)) != 0_u8
        end
        nil
      end

      def restore(enabled : UInt8, pending : UInt8) : Nil
        @enabled_mask = enabled
        @pending_mask = pending
      end

      private def bit(source : InterruptSource) : UInt8
        1_u8 << source.value
      end
    end
  end
end
