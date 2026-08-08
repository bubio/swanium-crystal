module Swanium
  module Core
    # Stateless SwanCrystal HyperVoice sample expansion and stereo routing.
    module WonderSwanHyperVoice
      def self.mix(ports : Bytes, scale : Int32) : Tuple(Int32, Int32)
        direct_left = signed_word(ports[0x64], ports[0x65])
        direct_right = signed_word(ports[0x66], ports[0x67])
        return {direct_left, direct_right} if direct_left != 0 || direct_right != 0

        control = ports[0x6A]
        shift = (control & 0x03_u8).to_i32
        data = ports[0x69]
        expanded = case control & 0x0C_u8
                   when 0x00_u8 then data.to_i32 << (8 - shift)
                   when 0x04_u8 then (data.to_i32 | -0x100) << (8 - shift)
                   when 0x08_u8 then data.unsafe_as(Int8).to_i32 << (8 - shift)
                   else              data.to_i32 << 8
                   end
        sample = (expanded & 0xFFFF).to_u16.unsafe_as(Int16).to_i32 >> 5
        sample *= scale
        routing = ports[0x6B]
        {(routing & 0x40_u8) != 0_u8 ? sample : 0_i32,
         (routing & 0x20_u8) != 0_u8 ? sample : 0_i32}
      end

      private def self.signed_word(low : UInt8, high : UInt8) : Int32
        (low.to_u16 | (high.to_u16 << 8)).unsafe_as(Int16).to_i32
      end
    end
  end
end
