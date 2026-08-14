module Swanium
  module Core
    # Memory-window capability of the WonderSwan family. Color and Crystal
    # expose all 64 KiB of internal RAM; the original model exposes 16 KiB.
    enum WonderSwanModel
      Mono
      Color
      Crystal

      def color? : Bool
        self != Mono
      end
    end

    # Bit positions in the WonderSwan INT_CAUSE / INT_ENABLE registers.
    # Higher-numbered sources have higher arbitration priority.
    enum WonderSwanInterrupt : UInt8
      SerialReceive = 0
      KeyPress      = 1
      Cartridge     = 2
      DmaComplete   = 3
      ScanlineMatch = 4
      VBlankTimer   = 5
      VBlank        = 6
      HBlankTimer   = 7
    end

    # Bit layout supplied by the platform layer to the keypad matrix.
    module WonderSwanKey
      Y1    = 1_u16 << 0
      Y2    = 1_u16 << 1
      Y3    = 1_u16 << 2
      Y4    = 1_u16 << 3
      X1    = 1_u16 << 4
      X2    = 1_u16 << 5
      X3    = 1_u16 << 6
      X4    = 1_u16 << 7
      Start = 1_u16 << 9
      A     = 1_u16 << 10
      B     = 1_u16 << 11
    end
  end
end
