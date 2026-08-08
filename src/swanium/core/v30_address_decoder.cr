require "./memory_bus"
require "./registers"

module Swanium
  module Core
    # Decoded ModRM operand, resolved before executing the instruction.
    struct RegisterOrMemory
      getter register_index : UInt8?
      getter memory_address : UInt32?

      def initialize(@register_index : UInt8? = nil, @memory_address : UInt32? = nil)
      end

      def register? : UInt8?
        @register_index
      end

      def memory? : UInt32?
        @memory_address
      end
    end

    struct ModRm
      getter reg : UInt8
      getter operand : RegisterOrMemory

      def initialize(@reg : UInt8, @operand : RegisterOrMemory)
      end
    end

    # Stateless V30 ModRM and effective-address decoder. It owns instruction
    # stream consumption and address formation, while Cpu retains instruction
    # semantics and commits the returned instruction pointer.
    module V30AddressDecoder
      def self.decode_mod_rm(bus : MemoryBus, registers : Registers,
                             segment_override : UInt16?) : Tuple(ModRm, UInt16)
        ip = registers.ip
        byte, ip = fetch_u8(bus, registers.cs, ip)
        mode = byte >> 6
        reg = (byte >> 3) & 0x07_u8
        rm = byte & 0x07_u8
        return {ModRm.new(reg, RegisterOrMemory.new(register_index: rm)), ip} if mode == 3_u8

        if mode == 0_u8 && rm == 6_u8
          offset, ip = fetch_u16(bus, registers.cs, ip)
          segment = segment_override || registers.ds
          return {ModRm.new(reg, RegisterOrMemory.new(memory_address: Core.linear_address(segment, offset))), ip}
        end

        base, use_stack_segment = effective_address_base(registers, rm)
        displacement, ip = displacement(bus, registers.cs, ip, mode)
        segment = segment_override || (use_stack_segment ? registers.ss : registers.ds)
        {ModRm.new(reg, RegisterOrMemory.new(memory_address: Core.linear_address(segment, base &+ displacement))), ip}
      end

      # LEA needs the raw offset rather than a segment-resolved address.
      def self.decode_effective_offset(bus : MemoryBus, registers : Registers) : Tuple(UInt8, UInt16, UInt16)
        ip = registers.ip
        byte, ip = fetch_u8(bus, registers.cs, ip)
        mode = byte >> 6
        reg = (byte >> 3) & 0x07_u8
        rm = byte & 0x07_u8
        return {reg, extended_register_offset(registers, rm), ip} if mode == 3_u8

        if mode == 0_u8 && rm == 6_u8
          offset, ip = fetch_u16(bus, registers.cs, ip)
          return {reg, offset, ip}
        end

        base, _use_stack_segment = effective_address_base(registers, rm)
        offset, ip = displacement(bus, registers.cs, ip, mode)
        {reg, base &+ offset, ip}
      end

      def self.extended_register_offset(registers : Registers, rm : UInt8) : UInt16
        case rm & 0x07_u8
        when 0_u8 then registers.bx &+ registers.ax
        when 1_u8 then registers.bx &+ registers.cx
        when 2_u8 then registers.bp &+ registers.dx
        when 3_u8 then registers.bp &+ registers.bx
        when 4_u8 then registers.si &+ registers.sp
        when 5_u8 then registers.di &+ registers.bp
        when 6_u8 then registers.bp &+ registers.si
        else           registers.bx &+ registers.di
        end
      end

      private def self.displacement(bus : MemoryBus, code_segment : UInt16, ip : UInt16,
                                    mode : UInt8) : Tuple(UInt16, UInt16)
        case mode
        when 0_u8
          {0_u16, ip}
        when 1_u8
          value, next_ip = fetch_u8(bus, code_segment, ip)
          {signed_byte(value), next_ip}
        else
          fetch_u16(bus, code_segment, ip)
        end
      end

      private def self.fetch_u8(bus : MemoryBus, code_segment : UInt16, ip : UInt16) : Tuple(UInt8, UInt16)
        {bus.read_u8(Core.linear_address(code_segment, ip)), ip &+ 1_u16}
      end

      private def self.fetch_u16(bus : MemoryBus, code_segment : UInt16, ip : UInt16) : Tuple(UInt16, UInt16)
        low, ip = fetch_u8(bus, code_segment, ip)
        high, ip = fetch_u8(bus, code_segment, ip)
        {low.to_u16 | (high.to_u16 << 8), ip}
      end

      private def self.effective_address_base(registers : Registers, rm : UInt8) : Tuple(UInt16, Bool)
        case rm
        when 0_u8 then {registers.bx &+ registers.si, false}
        when 1_u8 then {registers.bx &+ registers.di, false}
        when 2_u8 then {registers.bp &+ registers.si, true}
        when 3_u8 then {registers.bp &+ registers.di, true}
        when 4_u8 then {registers.si, false}
        when 5_u8 then {registers.di, false}
        when 6_u8 then {registers.bp, true}
        else           {registers.bx, false}
        end
      end

      private def self.signed_byte(value : UInt8) : UInt16
        value.bit(7) == 1 ? (0xFF00_u16 | value.to_u16) : value.to_u16
      end
    end
  end
end
