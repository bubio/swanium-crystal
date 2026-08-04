module Swanium
  module Core
    # General-purpose and segment registers of the NEC V30.
    #
    # The index methods intentionally use the 8086 ModRM encoding: 8-bit
    # registers are AL, CL, DL, BL, AH, CH, DH, BH; 16-bit registers are AX,
    # CX, DX, BX, SP, BP, SI, DI.
    struct Registers
      property ax : UInt16
      property cx : UInt16
      property dx : UInt16
      property bx : UInt16
      property sp : UInt16
      property bp : UInt16
      property si : UInt16
      property di : UInt16

      property cs : UInt16
      property ds : UInt16
      property ss : UInt16
      property es : UInt16
      property ip : UInt16

      def initialize(
        @ax : UInt16 = 0_u16, @cx : UInt16 = 0_u16, @dx : UInt16 = 0_u16, @bx : UInt16 = 0_u16,
        @sp : UInt16 = 0_u16, @bp : UInt16 = 0_u16, @si : UInt16 = 0_u16, @di : UInt16 = 0_u16,
        @cs : UInt16 = 0_u16, @ds : UInt16 = 0_u16, @ss : UInt16 = 0_u16, @es : UInt16 = 0_u16,
        @ip : UInt16 = 0_u16,
      )
      end

      def reg16(index : UInt8) : UInt16
        case index & 0x07_u8
        when 0 then @ax
        when 1 then @cx
        when 2 then @dx
        when 3 then @bx
        when 4 then @sp
        when 5 then @bp
        when 6 then @si
        else        @di
        end
      end

      def set_reg16(index : UInt8, value : UInt16) : Nil
        case index & 0x07_u8
        when 0 then @ax = value
        when 1 then @cx = value
        when 2 then @dx = value
        when 3 then @bx = value
        when 4 then @sp = value
        when 5 then @bp = value
        when 6 then @si = value
        else        @di = value
        end
      end

      def reg8(index : UInt8) : UInt8
        case index & 0x07_u8
        when 0 then (@ax & 0x00FF_u16).to_u8
        when 1 then (@cx & 0x00FF_u16).to_u8
        when 2 then (@dx & 0x00FF_u16).to_u8
        when 3 then (@bx & 0x00FF_u16).to_u8
        when 4 then (@ax >> 8).to_u8
        when 5 then (@cx >> 8).to_u8
        when 6 then (@dx >> 8).to_u8
        else        (@bx >> 8).to_u8
        end
      end

      def set_reg8(index : UInt8, value : UInt8) : Nil
        word = value.to_u16

        case index & 0x07_u8
        when 0 then @ax = (@ax & 0xFF00_u16) | word
        when 1 then @cx = (@cx & 0xFF00_u16) | word
        when 2 then @dx = (@dx & 0xFF00_u16) | word
        when 3 then @bx = (@bx & 0xFF00_u16) | word
        when 4 then @ax = (@ax & 0x00FF_u16) | (word << 8)
        when 5 then @cx = (@cx & 0x00FF_u16) | (word << 8)
        when 6 then @dx = (@dx & 0x00FF_u16) | (word << 8)
        else        @bx = (@bx & 0x00FF_u16) | (word << 8)
        end
      end

      # Segment-register encoding is ES, CS, SS, DS.
      def segment(index : UInt8) : UInt16
        case index & 0x03_u8
        when 0 then @es
        when 1 then @cs
        when 2 then @ss
        else        @ds
        end
      end

      def set_segment(index : UInt8, value : UInt16) : Nil
        case index & 0x03_u8
        when 0 then @es = value
        when 1 then @cs = value
        when 2 then @ss = value
        else        @ds = value
        end
      end
    end
  end
end
