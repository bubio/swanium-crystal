module Swanium
  module Core
    # V30 FLAGS register. Bit 1 always reads as one, matching 8086 behavior.
    struct Flags
      property carry : Bool
      property parity : Bool
      property auxiliary_carry : Bool
      property zero : Bool
      property sign : Bool
      property trap : Bool
      property interrupt : Bool
      property direction : Bool
      property overflow : Bool

      def initialize(
        @carry = false, @parity = false, @auxiliary_carry = false,
        @zero = false, @sign = false, @trap = false, @interrupt = false,
        @direction = false, @overflow = false,
      )
      end

      def to_u16 : UInt16
        value = 0x0002_u16
        value |= 0x0001_u16 if @carry
        value |= 0x0004_u16 if @parity
        value |= 0x0010_u16 if @auxiliary_carry
        value |= 0x0040_u16 if @zero
        value |= 0x0080_u16 if @sign
        value |= 0x0100_u16 if @trap
        value |= 0x0200_u16 if @interrupt
        value |= 0x0400_u16 if @direction
        value |= 0x0800_u16 if @overflow
        value
      end

      def self.from_u16(value : UInt16) : Flags
        Flags.new(
          carry: value.bit(0) == 1,
          parity: value.bit(2) == 1,
          auxiliary_carry: value.bit(4) == 1,
          zero: value.bit(6) == 1,
          sign: value.bit(7) == 1,
          trap: value.bit(8) == 1,
          interrupt: value.bit(9) == 1,
          direction: value.bit(10) == 1,
          overflow: value.bit(11) == 1
        )
      end

      # The parity flag covers only the least-significant result byte.
      def self.parity_even?(value : UInt8) : Bool
        value.popcount.even?
      end
    end
  end
end
