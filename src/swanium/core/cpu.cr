require "./flags"
require "./memory_bus"
require "./registers"

module Swanium
  module Core
    enum AluOperation
      Add
      Or
      Adc
      Sbb
      And
      Sub
      Xor
      Compare
    end

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

    struct CpuSnapshot
      getter registers : Registers
      getter flags : Flags
      getter halted : Bool

      def initialize(@registers : Registers, @flags : Flags, @halted : Bool)
      end
    end

    struct InstructionTrace
      getter code_segment : UInt16
      getter instruction_pointer : UInt16
      getter opcode : UInt8
      getter cycles : UInt32

      def initialize(@code_segment : UInt16, @instruction_pointer : UInt16, @opcode : UInt8, @cycles : UInt32)
      end
    end

    # Synchronous NEC V30 execution state. The opcode subset here establishes
    # the 8086-compatible data, stack, ALU, and branch paths used by the first
    # headless programs; unsupported instructions stop deterministically.
    class Cpu
      property registers : Registers
      property flags : Flags
      property halted : Bool
      getter fault_opcode : UInt8?
      getter last_trace : InstructionTrace?

      def initialize
        @registers = Registers.new
        @flags = Flags.new
        @halted = false
        @fault_opcode = nil
        @last_trace = nil
      end

      def reset(code_segment : UInt16, instruction_pointer : UInt16) : Nil
        @registers = Registers.new
        @flags = Flags.new
        @registers.cs = code_segment
        @registers.ip = instruction_pointer
        @registers.sp = 0x2000_u16
        @halted = false
        @fault_opcode = nil
        @last_trace = nil
      end

      def fetch_u8(bus : MemoryBus) : UInt8
        address = Core.linear_address(@registers.cs, @registers.ip)
        value = bus.read_u8(address)
        @registers.ip &+= 1_u16
        value
      end

      def fetch_u16(bus : MemoryBus) : UInt16
        low = fetch_u8(bus).to_u16
        high = fetch_u8(bus).to_u16
        low | (high << 8)
      end

      def step(bus : MemoryBus) : UInt32
        return 1_u32 if @halted

        code_segment = @registers.cs
        instruction_pointer = @registers.ip
        opcode = fetch_u8(bus)
        cycles = execute(opcode, bus)
        @last_trace = InstructionTrace.new(code_segment, instruction_pointer, opcode, cycles)
        cycles
      end

      def snapshot : CpuSnapshot
        CpuSnapshot.new(@registers, @flags, @halted)
      end

      def restore(snapshot : CpuSnapshot) : Nil
        @registers = snapshot.registers
        @flags = snapshot.flags
        @halted = snapshot.halted
        @fault_opcode = nil
        @last_trace = nil
      end

      # Accept an interrupt through the standard V30 real-mode vector table.
      # Masking is owned by InterruptController; this method deliberately also
      # serves software interrupts and exceptions.
      def service_interrupt(bus : MemoryBus, vector : UInt8) : UInt32
        push16(bus, @flags.to_u16)
        push16(bus, @registers.cs)
        push16(bus, @registers.ip)
        @flags.interrupt = false
        @flags.trap = false
        vector_address = vector.to_u32 << 2
        @registers.ip = bus.read_u16(vector_address)
        @registers.cs = bus.read_u16(vector_address + 2_u32)
        @halted = false
        10_u32
      end

      private def execute(opcode : UInt8, bus : MemoryBus) : UInt32
        base = opcode & 0xF8_u8
        form = opcode & 0x07_u8
        if form <= 5_u8 && alu_base?(base)
          return execute_alu_form(alu_operation(base >> 3), form, bus)
        end

        case opcode
        when 0x40_u8..0x47_u8
          index = opcode & 0x07_u8
          @registers.set_reg16(index, increment16(@registers.reg16(index)))
          1_u32
        when 0x48_u8..0x4F_u8
          index = opcode & 0x07_u8
          @registers.set_reg16(index, decrement16(@registers.reg16(index)))
          1_u32
        when 0x50_u8..0x57_u8
          push16(bus, @registers.reg16(opcode & 0x07_u8))
          1_u32
        when 0x58_u8..0x5F_u8
          @registers.set_reg16(opcode & 0x07_u8, pop16(bus))
          1_u32
        when 0x70_u8..0x7F_u8
          relative = signed_byte(fetch_u8(bus))
          if condition?(opcode)
            @registers.ip &+= relative
            5_u32
          else
            1_u32
          end
        when 0x80_u8, 0x82_u8
          execute_group1_8(bus)
        when 0x81_u8
          execute_group1_16(bus, fetch_u16(bus))
        when 0x83_u8
          execute_group1_16(bus, signed_byte(fetch_u8(bus)))
        when 0x88_u8
          mod_rm = decode_mod_rm(bus)
          write_operand8(bus, mod_rm.operand, @registers.reg8(mod_rm.reg))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0x89_u8
          mod_rm = decode_mod_rm(bus)
          write_operand16(bus, mod_rm.operand, @registers.reg16(mod_rm.reg))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0x8A_u8
          mod_rm = decode_mod_rm(bus)
          @registers.set_reg8(mod_rm.reg, read_operand8(bus, mod_rm.operand))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0x8B_u8
          mod_rm = decode_mod_rm(bus)
          @registers.set_reg16(mod_rm.reg, read_operand16(bus, mod_rm.operand))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0x90_u8
          1_u32
        when 0xB0_u8..0xB7_u8
          @registers.set_reg8(opcode & 0x07_u8, fetch_u8(bus))
          1_u32
        when 0xB8_u8..0xBF_u8
          @registers.set_reg16(opcode & 0x07_u8, fetch_u16(bus))
          1_u32
        when 0xC3_u8
          @registers.ip = pop16(bus)
          6_u32
        when 0xC6_u8
          mod_rm = decode_mod_rm(bus)
          write_operand8(bus, mod_rm.operand, fetch_u8(bus))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0xC7_u8
          mod_rm = decode_mod_rm(bus)
          write_operand16(bus, mod_rm.operand, fetch_u16(bus))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0xE8_u8
          relative = fetch_u16(bus)
          push16(bus, @registers.ip)
          @registers.ip &+= relative
          5_u32
        when 0xE9_u8
          @registers.ip &+= fetch_u16(bus)
          4_u32
        when 0xEB_u8
          @registers.ip &+= signed_byte(fetch_u8(bus))
          4_u32
        when 0xF4_u8
          @halted = true
          1_u32
        else
          @fault_opcode = opcode
          @halted = true
          1_u32
        end
      end

      private def alu_base?(base : UInt8) : Bool
        case base
        when 0x00_u8, 0x08_u8, 0x10_u8, 0x18_u8, 0x20_u8, 0x28_u8, 0x30_u8, 0x38_u8 then true
        else                                                                             false
        end
      end

      private def alu_operation(index : UInt8) : AluOperation
        AluOperation.from_value(index & 0x07_u8)
      end

      private def execute_alu_form(operation : AluOperation, form : UInt8, bus : MemoryBus) : UInt32
        case form
        when 0_u8
          mod_rm = decode_mod_rm(bus)
          result = alu8(operation, read_operand8(bus, mod_rm.operand), @registers.reg8(mod_rm.reg))
          write_operand8(bus, mod_rm.operand, result) unless operation.compare?
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 1_u8
          mod_rm = decode_mod_rm(bus)
          result = alu16(operation, read_operand16(bus, mod_rm.operand), @registers.reg16(mod_rm.reg))
          write_operand16(bus, mod_rm.operand, result) unless operation.compare?
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 2_u8
          mod_rm = decode_mod_rm(bus)
          result = alu8(operation, @registers.reg8(mod_rm.reg), read_operand8(bus, mod_rm.operand))
          @registers.set_reg8(mod_rm.reg, result) unless operation.compare?
          cycles(mod_rm.operand, 1_u32, 2_u32)
        when 3_u8
          mod_rm = decode_mod_rm(bus)
          result = alu16(operation, @registers.reg16(mod_rm.reg), read_operand16(bus, mod_rm.operand))
          @registers.set_reg16(mod_rm.reg, result) unless operation.compare?
          cycles(mod_rm.operand, 1_u32, 2_u32)
        when 4_u8
          result = alu8(operation, @registers.reg8(0_u8), fetch_u8(bus))
          @registers.set_reg8(0_u8, result) unless operation.compare?
          1_u32
        else
          result = alu16(operation, @registers.ax, fetch_u16(bus))
          @registers.ax = result unless operation.compare?
          1_u32
        end
      end

      private def execute_group1_8(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        operation = alu_operation(mod_rm.reg)
        result = alu8(operation, read_operand8(bus, mod_rm.operand), fetch_u8(bus))
        write_operand8(bus, mod_rm.operand, result) unless operation.compare?
        cycles(mod_rm.operand, 1_u32, 3_u32)
      end

      private def execute_group1_16(bus : MemoryBus, immediate : UInt16) : UInt32
        mod_rm = decode_mod_rm(bus)
        operation = alu_operation(mod_rm.reg)
        result = alu16(operation, read_operand16(bus, mod_rm.operand), immediate)
        write_operand16(bus, mod_rm.operand, result) unless operation.compare?
        cycles(mod_rm.operand, 1_u32, 3_u32)
      end

      private def decode_mod_rm(bus : MemoryBus) : ModRm
        byte = fetch_u8(bus)
        mode = byte >> 6
        reg = (byte >> 3) & 0x07_u8
        rm = byte & 0x07_u8
        return ModRm.new(reg, RegisterOrMemory.new(register_index: rm)) if mode == 3_u8

        if mode == 0_u8 && rm == 6_u8
          return ModRm.new(reg, RegisterOrMemory.new(memory_address: Core.linear_address(@registers.ds, fetch_u16(bus))))
        end

        base, use_stack_segment = effective_address_base(rm)
        displacement = case mode
                       when 0_u8 then 0_u16
                       when 1_u8 then signed_byte(fetch_u8(bus))
                       else           fetch_u16(bus)
                       end
        segment = use_stack_segment ? @registers.ss : @registers.ds
        ModRm.new(reg, RegisterOrMemory.new(memory_address: Core.linear_address(segment, base &+ displacement)))
      end

      private def effective_address_base(rm : UInt8) : Tuple(UInt16, Bool)
        case rm
        when 0_u8 then {@registers.bx &+ @registers.si, false}
        when 1_u8 then {@registers.bx &+ @registers.di, false}
        when 2_u8 then {@registers.bp &+ @registers.si, true}
        when 3_u8 then {@registers.bp &+ @registers.di, true}
        when 4_u8 then {@registers.si, false}
        when 5_u8 then {@registers.di, false}
        when 6_u8 then {@registers.bp, true}
        else           {@registers.bx, false}
        end
      end

      private def read_operand8(bus : MemoryBus, operand : RegisterOrMemory) : UInt8
        if index = operand.register?
          @registers.reg8(index)
        else
          bus.read_u8(operand.memory?.not_nil!)
        end
      end

      private def read_operand16(bus : MemoryBus, operand : RegisterOrMemory) : UInt16
        if index = operand.register?
          @registers.reg16(index)
        else
          bus.read_u16(operand.memory?.not_nil!)
        end
      end

      private def write_operand8(bus : MemoryBus, operand : RegisterOrMemory, value : UInt8) : Nil
        if index = operand.register?
          @registers.set_reg8(index, value)
        else
          bus.write_u8(operand.memory?.not_nil!, value)
        end
      end

      private def write_operand16(bus : MemoryBus, operand : RegisterOrMemory, value : UInt16) : Nil
        if index = operand.register?
          @registers.set_reg16(index, value)
        else
          bus.write_u16(operand.memory?.not_nil!, value)
        end
      end

      private def push16(bus : MemoryBus, value : UInt16) : Nil
        @registers.sp &-= 2_u16
        bus.write_u16(Core.linear_address(@registers.ss, @registers.sp), value)
      end

      private def pop16(bus : MemoryBus) : UInt16
        value = bus.read_u16(Core.linear_address(@registers.ss, @registers.sp))
        @registers.sp &+= 2_u16
        value
      end

      private def cycles(operand : RegisterOrMemory, register_cycles : UInt32, memory_cycles : UInt32) : UInt32
        operand.register? ? register_cycles : memory_cycles
      end

      private def signed_byte(value : UInt8) : UInt16
        value.bit(7) == 1 ? (0xFF00_u16 | value.to_u16) : value.to_u16
      end

      private def set_zsp8(value : UInt8) : Nil
        @flags.zero = value == 0_u8
        @flags.sign = value.bit(7) == 1
        @flags.parity = Flags.parity_even?(value)
      end

      private def set_zsp16(value : UInt16) : Nil
        @flags.zero = value == 0_u16
        @flags.sign = value.bit(15) == 1
        @flags.parity = Flags.parity_even?((value & 0x00FF_u16).to_u8)
      end

      private def alu8(operation : AluOperation, left : UInt8, right : UInt8) : UInt8
        case operation
        when .add?            then add8(left, right, 0_u8)
        when .adc?            then add8(left, right, @flags.carry ? 1_u8 : 0_u8)
        when .or?             then logic8(left | right)
        when .and?            then logic8(left & right)
        when .xor?            then logic8(left ^ right)
        when .sbb?            then subtract8(left, right, @flags.carry ? 1_u8 : 0_u8)
        when .sub?, .compare? then subtract8(left, right, 0_u8)
        else
          raise "unknown ALU operation"
        end
      end

      private def alu16(operation : AluOperation, left : UInt16, right : UInt16) : UInt16
        case operation
        when .add?            then add16(left, right, 0_u16)
        when .adc?            then add16(left, right, @flags.carry ? 1_u16 : 0_u16)
        when .or?             then logic16(left | right)
        when .and?            then logic16(left & right)
        when .xor?            then logic16(left ^ right)
        when .sbb?            then subtract16(left, right, @flags.carry ? 1_u16 : 0_u16)
        when .sub?, .compare? then subtract16(left, right, 0_u16)
        else
          raise "unknown ALU operation"
        end
      end

      private def add8(left : UInt8, right : UInt8, carry : UInt8) : UInt8
        wide = left.to_u16 + right.to_u16 + carry.to_u16
        result = (wide & 0x00FF_u16).to_u8
        @flags.carry = wide > 0x00FF_u16
        @flags.auxiliary_carry = (left & 0x0F_u8).to_u16 + (right & 0x0F_u8).to_u16 + carry.to_u16 > 0x0F_u16
        @flags.overflow = ((left ^ result) & (right ^ result) & 0x80_u8) != 0_u8
        set_zsp8(result)
        result
      end

      private def add16(left : UInt16, right : UInt16, carry : UInt16) : UInt16
        wide = left.to_u32 + right.to_u32 + carry.to_u32
        result = (wide & 0x0000_FFFF_u32).to_u16
        @flags.carry = wide > 0x0000_FFFF_u32
        @flags.auxiliary_carry = (left & 0x000F_u16).to_u32 + (right & 0x000F_u16).to_u32 + carry.to_u32 > 0x000F_u32
        @flags.overflow = ((left ^ result) & (right ^ result) & 0x8000_u16) != 0_u16
        set_zsp16(result)
        result
      end

      private def subtract8(left : UInt8, right : UInt8, borrow : UInt8) : UInt8
        result = left &- right &- borrow
        @flags.carry = left.to_u16 < right.to_u16 + borrow.to_u16
        @flags.auxiliary_carry = (left & 0x0F_u8).to_u16 < (right & 0x0F_u8).to_u16 + borrow.to_u16
        @flags.overflow = ((left ^ right) & (left ^ result) & 0x80_u8) != 0_u8
        set_zsp8(result)
        result
      end

      private def subtract16(left : UInt16, right : UInt16, borrow : UInt16) : UInt16
        result = left &- right &- borrow
        @flags.carry = left.to_u32 < right.to_u32 + borrow.to_u32
        @flags.auxiliary_carry = (left & 0x000F_u16).to_u32 < (right & 0x000F_u16).to_u32 + borrow.to_u32
        @flags.overflow = ((left ^ right) & (left ^ result) & 0x8000_u16) != 0_u16
        set_zsp16(result)
        result
      end

      private def logic8(result : UInt8) : UInt8
        @flags.carry = false
        @flags.overflow = false
        set_zsp8(result)
        result
      end

      private def logic16(result : UInt16) : UInt16
        @flags.carry = false
        @flags.overflow = false
        set_zsp16(result)
        result
      end

      private def increment16(value : UInt16) : UInt16
        result = value &+ 1_u16
        @flags.auxiliary_carry = (value & 0x000F_u16) == 0x000F_u16
        @flags.overflow = value == 0x7FFF_u16
        set_zsp16(result)
        result
      end

      private def decrement16(value : UInt16) : UInt16
        result = value &- 1_u16
        @flags.auxiliary_carry = (value & 0x000F_u16) == 0_u16
        @flags.overflow = value == 0x8000_u16
        set_zsp16(result)
        result
      end

      private def condition?(opcode : UInt8) : Bool
        case opcode & 0x0F_u8
        when  0 then @flags.overflow
        when  1 then !@flags.overflow
        when  2 then @flags.carry
        when  3 then !@flags.carry
        when  4 then @flags.zero
        when  5 then !@flags.zero
        when  6 then @flags.carry || @flags.zero
        when  7 then !@flags.carry && !@flags.zero
        when  8 then @flags.sign
        when  9 then !@flags.sign
        when 10 then @flags.parity
        when 11 then !@flags.parity
        when 12 then @flags.sign != @flags.overflow
        when 13 then @flags.sign == @flags.overflow
        when 14 then @flags.sign != @flags.overflow || @flags.zero
        else         @flags.sign == @flags.overflow && !@flags.zero
        end
      end
    end
  end
end
