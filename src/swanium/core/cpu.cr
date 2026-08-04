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

    enum ShiftOperation
      Rol
      Ror
      Rcl
      Rcr
      Shl
      Shr
      Sar
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
        @segment_override = nil
        @repeat_prefix = nil
        @interrupt_inhibit = 0_u8
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
        @segment_override = nil
        @repeat_prefix = nil
        @interrupt_inhibit = 0_u8
      end

      def fetch_u8(bus : MemoryBus) : UInt8
        address = Core.linear_address(@registers.cs, @registers.ip)
        value = bus.read_u8(address)
        @registers.ip &+= 1_u16
        value
      end

      # Consumes the one-instruction maskable-interrupt delay following STI
      # and SS loads. Called by the machine only at instruction boundaries.
      def maskable_interrupt_allowed? : Bool
        if @interrupt_inhibit > 0_u8
          @interrupt_inhibit -= 1_u8
          false
        else
          true
        end
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
        @segment_override = nil
        @repeat_prefix = nil
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
        @segment_override = nil
        @repeat_prefix = nil
        @interrupt_inhibit = 0_u8
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
        when 0xF2_u8, 0xF3_u8
          @repeat_prefix = opcode
          execute(fetch_u8(bus), bus)
        when 0x26_u8, 0x2E_u8, 0x36_u8, 0x3E_u8
          @segment_override = case opcode
                              when 0x26_u8 then @registers.es
                              when 0x2E_u8 then @registers.cs
                              when 0x36_u8 then @registers.ss
                              else              @registers.ds
                              end
          execute(fetch_u8(bus), bus)
        when 0x06_u8
          push16(bus, @registers.es); 1_u32
        when 0x07_u8
          @registers.es = pop16(bus); 1_u32
        when 0x0E_u8
          push16(bus, @registers.cs); 1_u32
        when 0x0F_u8
          1_u32
        when 0x16_u8
          push16(bus, @registers.ss); 1_u32
        when 0x17_u8
          @registers.ss = pop16(bus)
          @interrupt_inhibit = 1_u8
          1_u32
        when 0x1E_u8
          push16(bus, @registers.ds); 1_u32
        when 0x1F_u8
          @registers.ds = pop16(bus); 1_u32
        when 0x27_u8
          execute_daa
        when 0x2F_u8
          execute_das
        when 0x37_u8
          execute_aaa
        when 0x3F_u8
          execute_aas
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
        when 0x60_u8
          execute_pusha(bus)
        when 0x61_u8
          execute_popa(bus)
        when 0x62_u8
          execute_bound(bus)
        when 0x63_u8..0x67_u8
          1_u32
        when 0x6C_u8, 0x6D_u8, 0x6E_u8, 0x6F_u8
          execute_string(bus, opcode)
        when 0x68_u8
          push16(bus, fetch_u16(bus))
          1_u32
        when 0x6A_u8
          push16(bus, signed_byte(fetch_u8(bus)))
          1_u32
        when 0x69_u8
          execute_imul_immediate16(bus)
        when 0x6B_u8
          execute_imul_immediate8(bus)
        when 0x70_u8..0x7F_u8
          relative = signed_byte(fetch_u8(bus))
          if condition?(opcode)
            @registers.ip &+= relative
            5_u32
          else
            1_u32
          end
        when 0x84_u8
          mod_rm = decode_mod_rm(bus)
          logic8(read_operand8(bus, mod_rm.operand) & @registers.reg8(mod_rm.reg))
          cycles(mod_rm.operand, 1_u32, 2_u32)
        when 0x85_u8
          mod_rm = decode_mod_rm(bus)
          logic16(read_operand16(bus, mod_rm.operand) & @registers.reg16(mod_rm.reg))
          cycles(mod_rm.operand, 1_u32, 2_u32)
        when 0x86_u8
          mod_rm = decode_mod_rm(bus)
          left = read_operand8(bus, mod_rm.operand)
          right = @registers.reg8(mod_rm.reg)
          write_operand8(bus, mod_rm.operand, right)
          @registers.set_reg8(mod_rm.reg, left)
          cycles(mod_rm.operand, 3_u32, 5_u32)
        when 0x87_u8
          mod_rm = decode_mod_rm(bus)
          left = read_operand16(bus, mod_rm.operand)
          right = @registers.reg16(mod_rm.reg)
          write_operand16(bus, mod_rm.operand, right)
          @registers.set_reg16(mod_rm.reg, left)
          cycles(mod_rm.operand, 3_u32, 5_u32)
        when 0x80_u8, 0x82_u8
          execute_group1_8(bus)
        when 0x81_u8
          execute_group1_16(bus, false)
        when 0x83_u8
          execute_group1_16(bus, true)
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
        when 0x8C_u8
          mod_rm = decode_mod_rm(bus)
          write_operand16(bus, mod_rm.operand, @registers.segment(mod_rm.reg))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0x8D_u8
          reg, offset = decode_effective_offset(bus)
          @registers.set_reg16(reg, offset)
          1_u32
        when 0x8E_u8
          mod_rm = decode_mod_rm(bus)
          @registers.set_segment(mod_rm.reg, read_operand16(bus, mod_rm.operand))
          @interrupt_inhibit = 1_u8 if mod_rm.reg == 2_u8
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0x8F_u8
          execute_pop_rm16(bus)
        when 0x90_u8
          1_u32
        when 0x91_u8..0x97_u8
          index = opcode & 0x07_u8
          value = @registers.reg16(index)
          @registers.set_reg16(index, @registers.ax)
          @registers.ax = value
          3_u32
        when 0x98_u8
          @registers.ax = @registers.reg8(0_u8).bit(7) == 1 ? (0xFF00_u16 | @registers.reg8(0_u8).to_u16) : @registers.reg8(0_u8).to_u16
          1_u32
        when 0x99_u8
          @registers.dx = @registers.ax.bit(15) == 1 ? 0xFFFF_u16 : 0_u16
          1_u32
        when 0x9C_u8
          push16(bus, @flags.to_u16)
          2_u32
        when 0x9D_u8
          @flags = Flags.from_u16(pop16(bus))
          3_u32
        when 0x9E_u8
          @flags = Flags.from_u16((@flags.to_u16 & 0xFF00_u16) | @registers.reg8(4_u8).to_u16)
          4_u32
        when 0x9F_u8
          @registers.set_reg8(4_u8, (@flags.to_u16 & 0x00FF_u16).to_u8)
          2_u32
        when 0x9A_u8
          new_ip = fetch_u16(bus)
          new_cs = fetch_u16(bus)
          push16(bus, @registers.cs)
          push16(bus, @registers.ip)
          @registers.ip = new_ip
          @registers.cs = new_cs
          10_u32
        when 0x9B_u8
          # WAIT/FWAIT: no coprocessor exists on WonderSwan.
          1_u32
        when 0xA0_u8
          segment = @segment_override || @registers.ds
          @registers.set_reg8(0_u8, bus.read_u8(Core.linear_address(segment, fetch_u16(bus))))
          1_u32
        when 0xA4_u8
          execute_string(bus, opcode)
        when 0xA5_u8, 0xA6_u8, 0xA7_u8
          execute_string(bus, opcode)
        when 0xAA_u8
          execute_string(bus, opcode)
        when 0xAB_u8, 0xAC_u8, 0xAD_u8, 0xAE_u8, 0xAF_u8
          execute_string(bus, opcode)
        when 0xA1_u8
          segment = @segment_override || @registers.ds
          @registers.ax = bus.read_u16(Core.linear_address(segment, fetch_u16(bus)))
          1_u32
        when 0xA2_u8
          segment = @segment_override || @registers.ds
          bus.write_u8(Core.linear_address(segment, fetch_u16(bus)), @registers.reg8(0_u8))
          1_u32
        when 0xA3_u8
          segment = @segment_override || @registers.ds
          bus.write_u16(Core.linear_address(segment, fetch_u16(bus)), @registers.ax)
          1_u32
        when 0xA8_u8
          logic8(@registers.reg8(0_u8) & fetch_u8(bus))
          1_u32
        when 0xA9_u8
          logic16(@registers.ax & fetch_u16(bus))
          1_u32
        when 0xB0_u8..0xB7_u8
          @registers.set_reg8(opcode & 0x07_u8, fetch_u8(bus))
          1_u32
        when 0xB8_u8..0xBF_u8
          @registers.set_reg16(opcode & 0x07_u8, fetch_u16(bus))
          1_u32
        when 0xC0_u8
          execute_shift8_immediate(bus)
        when 0xC1_u8
          execute_shift16_immediate(bus)
        when 0xC2_u8
          extra = fetch_u16(bus)
          @registers.ip = pop16(bus)
          @registers.sp &+= extra
          6_u32
        when 0xC3_u8
          @registers.ip = pop16(bus)
          6_u32
        when 0xC4_u8
          execute_load_far_pointer(bus, true)
        when 0xC5_u8
          execute_load_far_pointer(bus, false)
        when 0xCA_u8
          extra = fetch_u16(bus)
          @registers.ip = pop16(bus)
          @registers.cs = pop16(bus)
          @registers.sp &+= extra
          9_u32
        when 0xCB_u8
          @registers.ip = pop16(bus)
          @registers.cs = pop16(bus)
          8_u32
        when 0xCC_u8
          service_interrupt(bus, 3_u8)
        when 0xCD_u8
          service_interrupt(bus, fetch_u8(bus))
        when 0xCE_u8
          @flags.overflow ? service_interrupt(bus, 4_u8) : 6_u32
        when 0xCF_u8
          @registers.ip = pop16(bus)
          @registers.cs = pop16(bus)
          old_interrupt = @flags.interrupt
          @flags = Flags.from_u16(pop16(bus))
          @interrupt_inhibit = 1_u8 if !old_interrupt && @flags.interrupt
          10_u32
        when 0xC6_u8
          mod_rm = decode_mod_rm(bus)
          write_operand8(bus, mod_rm.operand, fetch_u8(bus))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0xC7_u8
          mod_rm = decode_mod_rm(bus)
          write_operand16(bus, mod_rm.operand, fetch_u16(bus))
          cycles(mod_rm.operand, 1_u32, 1_u32)
        when 0xC8_u8
          execute_enter(bus)
        when 0xC9_u8
          @registers.sp = @registers.bp
          @registers.bp = pop16(bus)
          2_u32
        when 0xD0_u8
          execute_shift8(bus, 1_u8)
        when 0xD1_u8
          execute_shift16(bus, 1_u8)
        when 0xD2_u8
          execute_shift8(bus, @registers.reg8(1_u8))
        when 0xD3_u8
          execute_shift16(bus, @registers.reg8(1_u8))
        when 0xD4_u8
          execute_aam(bus)
        when 0xD5_u8
          execute_aad(bus)
        when 0xD6_u8
          @registers.set_reg8(0_u8, @flags.carry ? 0xFF_u8 : 0_u8)
          3_u32
        when 0xD7_u8
          offset = @registers.bx &+ @registers.reg8(0_u8).to_u16
          @registers.set_reg8(0_u8, bus.read_u8(Core.linear_address(@registers.ds, offset)))
          5_u32
        when 0xD8_u8..0xDF_u8
          consume_esc(bus)
        when 0xE8_u8
          relative = fetch_u16(bus)
          push16(bus, @registers.ip)
          @registers.ip &+= relative
          5_u32
        when 0xE0_u8..0xE2_u8
          relative = signed_byte(fetch_u8(bus))
          @registers.cx &-= 1_u16
          repeat = case opcode
                   when 0xE0_u8 then @registers.cx != 0_u16 && !@flags.zero
                   when 0xE1_u8 then @registers.cx != 0_u16 && @flags.zero
                   else              @registers.cx != 0_u16
                   end
          if repeat
            @registers.ip &+= relative
            6_u32
          else
            2_u32
          end
        when 0xE3_u8
          relative = signed_byte(fetch_u8(bus))
          if @registers.cx == 0_u16
            @registers.ip &+= relative
            4_u32
          else
            1_u32
          end
        when 0xE4_u8
          @registers.set_reg8(0_u8, bus.read_io(fetch_u8(bus)))
          4_u32
        when 0xE5_u8
          port = fetch_u8(bus)
          @registers.ax = bus.read_io(port).to_u16 | (bus.read_io(port &+ 1_u8).to_u16 << 8)
          4_u32
        when 0xE6_u8
          bus.write_io(fetch_u8(bus), @registers.reg8(0_u8))
          4_u32
        when 0xE7_u8
          port = fetch_u8(bus)
          bus.write_io(port, @registers.reg8(0_u8))
          bus.write_io(port &+ 1_u8, @registers.reg8(4_u8))
          4_u32
        when 0xE9_u8
          @registers.ip &+= fetch_u16(bus)
          4_u32
        when 0xEA_u8
          @registers.ip = fetch_u16(bus)
          @registers.cs = fetch_u16(bus)
          7_u32
        when 0xEB_u8
          @registers.ip &+= signed_byte(fetch_u8(bus))
          4_u32
        when 0xEC_u8
          @registers.set_reg8(0_u8, bus.read_io(@registers.reg8(2_u8)))
          4_u32
        when 0xED_u8
          port = @registers.reg8(2_u8)
          @registers.ax = bus.read_io(port).to_u16 | (bus.read_io(port &+ 1_u8).to_u16 << 8)
          4_u32
        when 0xEE_u8
          bus.write_io(@registers.reg8(2_u8), @registers.reg8(0_u8))
          4_u32
        when 0xEF_u8
          port = @registers.reg8(2_u8)
          bus.write_io(port, @registers.reg8(0_u8))
          bus.write_io(port &+ 1_u8, @registers.reg8(4_u8))
          4_u32
        when 0xF6_u8
          execute_group3_8(bus)
        when 0xF7_u8
          execute_group3_16(bus)
        when 0xF0_u8
          execute(fetch_u8(bus), bus)
        when 0xF1_u8
          service_interrupt(bus, 1_u8)
        when 0xFE_u8
          execute_group4(bus)
        when 0xFF_u8
          execute_group5(bus)
        when 0xF4_u8
          @halted = true
          1_u32
        when 0xF5_u8
          @flags.carry = !@flags.carry
          1_u32
        when 0xF8_u8
          @flags.carry = false
          1_u32
        when 0xF9_u8
          @flags.carry = true
          1_u32
        when 0xFA_u8
          @flags.interrupt = false
          1_u32
        when 0xFB_u8
          was_enabled = @flags.interrupt
          @flags.interrupt = true
          @interrupt_inhibit = 1_u8 unless was_enabled
          1_u32
        when 0xFC_u8
          @flags.direction = false
          1_u32
        when 0xFD_u8
          @flags.direction = true
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

      private def execute_group1_16(bus : MemoryBus, sign_extend : Bool) : UInt32
        mod_rm = decode_mod_rm(bus)
        immediate = sign_extend ? signed_byte(fetch_u8(bus)) : fetch_u16(bus)
        operation = alu_operation(mod_rm.reg)
        result = alu16(operation, read_operand16(bus, mod_rm.operand), immediate)
        write_operand16(bus, mod_rm.operand, result) unless operation.compare?
        cycles(mod_rm.operand, 1_u32, 3_u32)
      end

      private def execute_daa : UInt32
        original = @registers.reg8(0_u8)
        result = original
        if (original & 0x0F_u8) > 9_u8 || @flags.auxiliary_carry
          result &+= 6_u8
          @flags.auxiliary_carry = true
        else
          @flags.auxiliary_carry = false
        end
        @flags.carry = original > 0x99_u8 || @flags.carry
        result &+= 0x60_u8 if @flags.carry
        @registers.set_reg8(0_u8, result)
        set_zsp8(result)
        10_u32
      end

      private def execute_das : UInt32
        original = @registers.reg8(0_u8)
        result = original
        if (original & 0x0F_u8) > 9_u8 || @flags.auxiliary_carry
          result &-= 6_u8
          @flags.auxiliary_carry = true
        else
          @flags.auxiliary_carry = false
        end
        @flags.carry = original > 0x99_u8 || @flags.carry
        result &-= 0x60_u8 if @flags.carry
        @registers.set_reg8(0_u8, result)
        set_zsp8(result)
        10_u32
      end

      private def execute_aaa : UInt32
        al = @registers.reg8(0_u8)
        ah = @registers.reg8(4_u8)
        if (al & 0x0F_u8) > 9_u8 || @flags.auxiliary_carry
          @registers.set_reg8(0_u8, (al &+ 6_u8) & 0x0F_u8)
          @registers.set_reg8(4_u8, ah &+ 1_u8)
          @flags.auxiliary_carry = true
          @flags.carry = true
        else
          @registers.set_reg8(0_u8, al & 0x0F_u8)
          @flags.auxiliary_carry = false
          @flags.carry = false
        end
        9_u32
      end

      private def execute_aas : UInt32
        al = @registers.reg8(0_u8)
        ah = @registers.reg8(4_u8)
        if (al & 0x0F_u8) > 9_u8 || @flags.auxiliary_carry
          @registers.set_reg8(0_u8, (al &- 6_u8) & 0x0F_u8)
          @registers.set_reg8(4_u8, ah &- 1_u8)
          @flags.auxiliary_carry = true
          @flags.carry = true
        else
          @registers.set_reg8(0_u8, al & 0x0F_u8)
          @flags.auxiliary_carry = false
          @flags.carry = false
        end
        9_u32
      end

      private def execute_aam(bus : MemoryBus) : UInt32
        base = fetch_u8(bus)
        return service_interrupt(bus, 0_u8) if base == 0_u8

        al = @registers.reg8(0_u8)
        @registers.set_reg8(4_u8, al // base)
        @registers.set_reg8(0_u8, al % base)
        set_zsp8(@registers.reg8(0_u8))
        17_u32
      end

      private def execute_aad(bus : MemoryBus) : UInt32
        base = fetch_u8(bus)
        result = @registers.reg8(4_u8) &* base &+ @registers.reg8(0_u8)
        @registers.ax = result.to_u16
        set_zsp8(result)
        6_u32
      end

      private def execute_enter(bus : MemoryBus) : UInt32
        size = fetch_u16(bus)
        level = fetch_u8(bus) & 0x1F_u8
        old_bp = @registers.bp
        push16(bus, old_bp)
        frame = @registers.sp
        if level > 0_u8
          (1_u8...level).each do
            @registers.bp &-= 2_u16
            push16(bus, bus.read_u16(Core.linear_address(@registers.ss, @registers.bp)))
          end
          push16(bus, frame)
        end
        @registers.bp = frame
        @registers.sp &-= size
        8_u32
      end

      private def execute_shift8(bus : MemoryBus, count : UInt8) : UInt32
        mod_rm = decode_mod_rm(bus)
        result = shift8(shift_operation(mod_rm.reg), read_operand8(bus, mod_rm.operand), count)
        write_operand8(bus, mod_rm.operand, result)
        cycles(mod_rm.operand, count == 1_u8 ? 1_u32 : 3_u32, count == 1_u8 ? 3_u32 : 5_u32)
      end

      private def execute_shift8_immediate(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        count = fetch_u8(bus)
        if mod_rm.reg == 6_u8
          write_operand8(bus, mod_rm.operand, 0_u8)
          return cycles(mod_rm.operand, 3_u32, 5_u32)
        end
        result = shift8(shift_operation(mod_rm.reg), read_operand8(bus, mod_rm.operand), count)
        write_operand8(bus, mod_rm.operand, result)
        cycles(mod_rm.operand, 3_u32, 5_u32)
      end

      private def execute_shift16(bus : MemoryBus, count : UInt8) : UInt32
        mod_rm = decode_mod_rm(bus)
        result = shift16(shift_operation(mod_rm.reg), read_operand16(bus, mod_rm.operand), count)
        write_operand16(bus, mod_rm.operand, result)
        cycles(mod_rm.operand, count == 1_u8 ? 1_u32 : 3_u32, count == 1_u8 ? 3_u32 : 5_u32)
      end

      private def execute_shift16_immediate(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        count = fetch_u8(bus)
        if mod_rm.reg == 6_u8
          write_operand16(bus, mod_rm.operand, 0_u16)
          return cycles(mod_rm.operand, 3_u32, 5_u32)
        end
        result = shift16(shift_operation(mod_rm.reg), read_operand16(bus, mod_rm.operand), count)
        write_operand16(bus, mod_rm.operand, result)
        cycles(mod_rm.operand, 3_u32, 5_u32)
      end

      private def execute_group3_8(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        case mod_rm.reg
        when 0_u8
          logic8(read_operand8(bus, mod_rm.operand) & fetch_u8(bus))
          cycles(mod_rm.operand, 1_u32, 2_u32)
        when 1_u8
          fetch_u8(bus)
          1_u32
        when 2_u8
          write_operand8(bus, mod_rm.operand, ~read_operand8(bus, mod_rm.operand))
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 3_u8
          value = read_operand8(bus, mod_rm.operand)
          result = subtract8(0_u8, value, 0_u8)
          write_operand8(bus, mod_rm.operand, result)
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 4_u8
          product = @registers.reg8(0_u8).to_u16 * read_operand8(bus, mod_rm.operand).to_u16
          @registers.ax = product
          @flags.carry = product > 0x00FF_u16
          @flags.overflow = @flags.carry
          cycles(mod_rm.operand, 3_u32, 4_u32)
        when 5_u8
          product = signed8(@registers.reg8(0_u8)) * signed8(read_operand8(bus, mod_rm.operand))
          @registers.ax = (product & 0xFFFF).to_u16
          @flags.carry = product < -128 || product > 127
          @flags.overflow = @flags.carry
          cycles(mod_rm.operand, 3_u32, 4_u32)
        when 6_u8
          divisor = read_operand8(bus, mod_rm.operand)
          dividend = @registers.ax
          if divisor == 0_u8 || dividend / divisor.to_u16 > 0x00FF_u16
            service_interrupt(bus, 0_u8)
          else
            quotient = (dividend / divisor.to_u16).to_u8
            remainder = (dividend % divisor.to_u16).to_u8
            @registers.set_reg8(0_u8, quotient)
            @registers.set_reg8(4_u8, remainder)
          end
          cycles(mod_rm.operand, 15_u32, 24_u32)
        else
          divisor = signed8(read_operand8(bus, mod_rm.operand))
          dividend = signed16(@registers.ax)
          if divisor == 0
            service_interrupt(bus, 0_u8)
          else
            quotient = dividend // divisor
            if quotient < -128 || quotient > 127
              service_interrupt(bus, 0_u8)
              return cycles(mod_rm.operand, 17_u32, 25_u32)
            end
            @registers.set_reg8(0_u8, (quotient & 0xFF).to_u8)
            @registers.set_reg8(4_u8, ((dividend % divisor) & 0xFF).to_u8)
          end
          cycles(mod_rm.operand, 17_u32, 25_u32)
        end
      end

      private def execute_group3_16(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        case mod_rm.reg
        when 0_u8
          logic16(read_operand16(bus, mod_rm.operand) & fetch_u16(bus))
          cycles(mod_rm.operand, 1_u32, 2_u32)
        when 1_u8
          fetch_u16(bus)
          1_u32
        when 2_u8
          write_operand16(bus, mod_rm.operand, ~read_operand16(bus, mod_rm.operand))
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 3_u8
          value = read_operand16(bus, mod_rm.operand)
          result = subtract16(0_u16, value, 0_u16)
          write_operand16(bus, mod_rm.operand, result)
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 4_u8
          product = @registers.ax.to_u32 * read_operand16(bus, mod_rm.operand).to_u32
          @registers.ax = (product & 0xFFFF_u32).to_u16
          @registers.dx = (product >> 16).to_u16
          @flags.carry = product > 0xFFFF_u32
          @flags.overflow = @flags.carry
          cycles(mod_rm.operand, 3_u32, 4_u32)
        when 5_u8
          product = signed16(@registers.ax).to_i64 * signed16(read_operand16(bus, mod_rm.operand)).to_i64
          @registers.ax = (product & 0xFFFF).to_u16
          @registers.dx = ((product >> 16) & 0xFFFF).to_u16
          @flags.carry = product < -32_768 || product > 32_767
          @flags.overflow = @flags.carry
          cycles(mod_rm.operand, 3_u32, 4_u32)
        when 6_u8
          divisor = read_operand16(bus, mod_rm.operand)
          dividend = (@registers.dx.to_u32 << 16) | @registers.ax.to_u32
          if divisor == 0_u16 || dividend / divisor.to_u32 > 0xFFFF_u32
            service_interrupt(bus, 0_u8)
          else
            @registers.ax = (dividend / divisor.to_u32).to_u16
            @registers.dx = (dividend % divisor.to_u32).to_u16
          end
          cycles(mod_rm.operand, 15_u32, 24_u32)
        else
          divisor = signed16(read_operand16(bus, mod_rm.operand)).to_i64
          dividend = signed32((@registers.dx.to_u32 << 16) | @registers.ax.to_u32).to_i64
          if divisor == 0
            service_interrupt(bus, 0_u8)
          else
            quotient = dividend // divisor
            if quotient < -32_768 || quotient > 32_767
              service_interrupt(bus, 0_u8)
              return cycles(mod_rm.operand, 17_u32, 25_u32)
            end
            @registers.ax = (quotient & 0xFFFF).to_u16
            @registers.dx = ((dividend % divisor) & 0xFFFF).to_u16
          end
          cycles(mod_rm.operand, 17_u32, 25_u32)
        end
      end

      private def execute_pusha(bus : MemoryBus) : UInt32
        original_sp = @registers.sp
        push16(bus, @registers.ax)
        push16(bus, @registers.cx)
        push16(bus, @registers.dx)
        push16(bus, @registers.bx)
        push16(bus, original_sp)
        push16(bus, @registers.bp)
        push16(bus, @registers.si)
        push16(bus, @registers.di)
        9_u32
      end

      private def execute_popa(bus : MemoryBus) : UInt32
        @registers.di = pop16(bus)
        @registers.si = pop16(bus)
        @registers.bp = pop16(bus)
        pop16(bus)
        @registers.bx = pop16(bus)
        @registers.dx = pop16(bus)
        @registers.cx = pop16(bus)
        @registers.ax = pop16(bus)
        8_u32
      end

      private def execute_bound(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        unless address = mod_rm.operand.memory?
          @fault_opcode = 0x62_u8
          @halted = true
          return 1_u32
        end
        index = signed16(@registers.reg16(mod_rm.reg))
        lower = signed16(bus.read_u16(address))
        upper = signed16(bus.read_u16(address &+ 2_u32))
        service_interrupt(bus, 5_u8) if index < lower || index > upper
        13_u32
      end

      private def execute_pop_rm16(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        return 1_u32 unless mod_rm.reg == 0_u8

        write_operand16(bus, mod_rm.operand, pop16(bus))
        cycles(mod_rm.operand, 1_u32, 3_u32)
      end

      private def execute_group4(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        case mod_rm.reg
        when 0_u8
          write_operand8(bus, mod_rm.operand, increment8(read_operand8(bus, mod_rm.operand)))
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 1_u8
          write_operand8(bus, mod_rm.operand, decrement8(read_operand8(bus, mod_rm.operand)))
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 6_u8
          push16(bus, read_operand16(bus, mod_rm.operand))
          cycles(mod_rm.operand, 1_u32, 2_u32)
        else
          1_u32
        end
      end

      # The WonderSwan has no external x87. ESC still consumes its ModRM
      # encoding so the following instruction is fetched at the correct IP.
      private def consume_esc(bus : MemoryBus) : UInt32
        byte = fetch_u8(bus)
        mode = byte >> 6
        rm = byte & 0x07_u8
        if mode == 0_u8 && rm == 6_u8
          fetch_u16(bus)
        elsif mode == 1_u8
          fetch_u8(bus)
        elsif mode == 2_u8
          fetch_u16(bus)
        end
        1_u32
      end

      private def execute_imul_immediate16(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        immediate = fetch_u16(bus)
        execute_imul_immediate(bus, mod_rm, immediate)
      end

      private def execute_imul_immediate8(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        execute_imul_immediate(bus, mod_rm, signed_byte(fetch_u8(bus)))
      end

      private def execute_imul_immediate(bus : MemoryBus, mod_rm : ModRm, immediate : UInt16) : UInt32
        product = signed16(read_operand16(bus, mod_rm.operand)).to_i64 * signed16(immediate).to_i64
        @registers.set_reg16(mod_rm.reg, (product & 0xFFFF).to_u16)
        @flags.carry = product < -32_768 || product > 32_767
        @flags.overflow = @flags.carry
        cycles(mod_rm.operand, 3_u32, 4_u32)
      end

      private def execute_group5(bus : MemoryBus) : UInt32
        mod_rm = decode_mod_rm(bus)
        case mod_rm.reg
        when 0_u8
          write_operand16(bus, mod_rm.operand, increment16(read_operand16(bus, mod_rm.operand)))
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 1_u8
          write_operand16(bus, mod_rm.operand, decrement16(read_operand16(bus, mod_rm.operand)))
          cycles(mod_rm.operand, 1_u32, 3_u32)
        when 2_u8
          target = read_operand16(bus, mod_rm.operand)
          push16(bus, @registers.ip)
          @registers.ip = target
          cycles(mod_rm.operand, 5_u32, 6_u32)
        when 3_u8
          return unsupported_group5 unless address = mod_rm.operand.memory?
          new_ip = bus.read_u16(address)
          new_cs = bus.read_u16(address &+ 2_u32)
          push16(bus, @registers.cs)
          push16(bus, @registers.ip)
          @registers.ip = new_ip
          @registers.cs = new_cs
          9_u32
        when 4_u8
          @registers.ip = read_operand16(bus, mod_rm.operand)
          cycles(mod_rm.operand, 3_u32, 5_u32)
        when 5_u8
          return unsupported_group5 unless address = mod_rm.operand.memory?
          @registers.ip = bus.read_u16(address)
          @registers.cs = bus.read_u16(address &+ 2_u32)
          9_u32
        when 6_u8
          push16(bus, read_operand16(bus, mod_rm.operand))
          cycles(mod_rm.operand, 1_u32, 2_u32)
        else
          # V30 compatibility: FF /7 consumes ModRM but has no effect.
          1_u32
        end
      end

      private def unsupported_group5 : UInt32
        @fault_opcode = 0xFF_u8
        @halted = true
        1_u32
      end

      private def shift_operation(reg : UInt8) : ShiftOperation
        case reg & 0x07_u8
        when 0_u8       then ShiftOperation::Rol
        when 1_u8       then ShiftOperation::Ror
        when 2_u8       then ShiftOperation::Rcl
        when 3_u8       then ShiftOperation::Rcr
        when 4_u8, 6_u8 then ShiftOperation::Shl
        when 5_u8       then ShiftOperation::Shr
        else                 ShiftOperation::Sar
        end
      end

      private def shift8(operation : ShiftOperation, value : UInt8, count : UInt8) : UInt8
        return value if count == 0_u8

        original_msb = value.bit(7) == 1
        result = value
        count.times { result = shift_step8(operation, result) }
        set_zsp8(result) if operation.shl? || operation.shr? || operation.sar?
        if count == 1_u8
          @flags.overflow = case operation
                            when .shl? then (result.bit(7) == 1) != @flags.carry
                            when .shr? then original_msb
                            when .sar? then false
                            else            @flags.overflow
                            end
        end
        result
      end

      private def shift16(operation : ShiftOperation, value : UInt16, count : UInt8) : UInt16
        return value if count == 0_u8

        original_msb = value.bit(15) == 1
        result = value
        count.times { result = shift_step16(operation, result) }
        set_zsp16(result) if operation.shl? || operation.shr? || operation.sar?
        if count == 1_u8
          @flags.overflow = case operation
                            when .shl? then (result.bit(15) == 1) != @flags.carry
                            when .shr? then original_msb
                            when .sar? then false
                            else            @flags.overflow
                            end
        end
        result
      end

      private def shift_step8(operation : ShiftOperation, value : UInt8) : UInt8
        case operation
        when .rol?
          carry = value.bit(7) == 1; @flags.carry = carry; (value << 1) | (carry ? 1_u8 : 0_u8)
        when .ror?
          carry = value.bit(0) == 1; @flags.carry = carry; (value >> 1) | (carry ? 0x80_u8 : 0_u8)
        when .rcl?
          carry_in = @flags.carry ? 1_u8 : 0_u8; @flags.carry = value.bit(7) == 1; (value << 1) | carry_in
        when .rcr?
          carry_in = @flags.carry ? 0x80_u8 : 0_u8; @flags.carry = value.bit(0) == 1; (value >> 1) | carry_in
        when .shl?
          @flags.carry = value.bit(7) == 1; value << 1
        when .shr?
          @flags.carry = value.bit(0) == 1; value >> 1
        else
          @flags.carry = value.bit(0) == 1; (value >> 1) | (value.bit(7) == 1 ? 0x80_u8 : 0_u8)
        end
      end

      private def shift_step16(operation : ShiftOperation, value : UInt16) : UInt16
        case operation
        when .rol?
          carry = value.bit(15) == 1; @flags.carry = carry; (value << 1) | (carry ? 1_u16 : 0_u16)
        when .ror?
          carry = value.bit(0) == 1; @flags.carry = carry; (value >> 1) | (carry ? 0x8000_u16 : 0_u16)
        when .rcl?
          carry_in = @flags.carry ? 1_u16 : 0_u16; @flags.carry = value.bit(15) == 1; (value << 1) | carry_in
        when .rcr?
          carry_in = @flags.carry ? 0x8000_u16 : 0_u16; @flags.carry = value.bit(0) == 1; (value >> 1) | carry_in
        when .shl?
          @flags.carry = value.bit(15) == 1; value << 1
        when .shr?
          @flags.carry = value.bit(0) == 1; value >> 1
        else
          @flags.carry = value.bit(0) == 1; (value >> 1) | (value.bit(15) == 1 ? 0x8000_u16 : 0_u16)
        end
      end

      private def decode_mod_rm(bus : MemoryBus) : ModRm
        byte = fetch_u8(bus)
        mode = byte >> 6
        reg = (byte >> 3) & 0x07_u8
        rm = byte & 0x07_u8
        return ModRm.new(reg, RegisterOrMemory.new(register_index: rm)) if mode == 3_u8

        if mode == 0_u8 && rm == 6_u8
          segment = @segment_override || @registers.ds
          return ModRm.new(reg, RegisterOrMemory.new(memory_address: Core.linear_address(segment, fetch_u16(bus))))
        end

        base, use_stack_segment = effective_address_base(rm)
        displacement = case mode
                       when 0_u8 then 0_u16
                       when 1_u8 then signed_byte(fetch_u8(bus))
                       else           fetch_u16(bus)
                       end
        segment = @segment_override || (use_stack_segment ? @registers.ss : @registers.ds)
        ModRm.new(reg, RegisterOrMemory.new(memory_address: Core.linear_address(segment, base &+ displacement)))
      end

      # LEA needs the raw 16-bit offset, not the segment-resolved address that
      # regular ModRM decoding returns. V30 also defines an extended register
      # mode address table used by the CPU conformance tests.
      private def decode_effective_offset(bus : MemoryBus) : Tuple(UInt8, UInt16)
        byte = fetch_u8(bus)
        mode = byte >> 6
        reg = (byte >> 3) & 0x07_u8
        rm = byte & 0x07_u8
        return {reg, extended_register_offset(rm)} if mode == 3_u8
        return {reg, fetch_u16(bus)} if mode == 0_u8 && rm == 6_u8

        base, ignored_stack_segment = effective_address_base(rm)
        displacement = case mode
                       when 0_u8 then 0_u16
                       when 1_u8 then signed_byte(fetch_u8(bus))
                       else           fetch_u16(bus)
                       end
        {reg, base &+ displacement}
      end

      private def extended_register_offset(rm : UInt8) : UInt16
        case rm & 0x07_u8
        when 0_u8 then @registers.bx &+ @registers.ax
        when 1_u8 then @registers.bx &+ @registers.cx
        when 2_u8 then @registers.bp &+ @registers.dx
        when 3_u8 then @registers.bp &+ @registers.bx
        when 4_u8 then @registers.si &+ @registers.sp
        when 5_u8 then @registers.di &+ @registers.bp
        when 6_u8 then @registers.bp &+ @registers.si
        else           @registers.bx &+ @registers.di
        end
      end

      private def execute_load_far_pointer(bus : MemoryBus, es : Bool) : UInt32
        mod_rm = decode_mod_rm(bus)
        unless address = mod_rm.operand.memory?
          @fault_opcode = es ? 0xC4_u8 : 0xC5_u8
          @halted = true
          return 1_u32
        end
        @registers.set_reg16(mod_rm.reg, bus.read_u16(address))
        segment = bus.read_u16(address &+ 2_u32)
        es ? (@registers.es = segment) : (@registers.ds = segment)
        6_u32
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

      private def signed8(value : UInt8) : Int16
        value.bit(7) == 1 ? value.to_i16 - 256 : value.to_i16
      end

      private def signed16(value : UInt16) : Int32
        value.bit(15) == 1 ? value.to_i32 - 65_536 : value.to_i32
      end

      private def signed32(value : UInt32) : Int64
        value.bit(31) == 1 ? value.to_i64 - 4_294_967_296_i64 : value.to_i64
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

      private def increment8(value : UInt8) : UInt8
        result = value &+ 1_u8
        @flags.auxiliary_carry = (value & 0x0F_u8) == 0x0F_u8
        @flags.overflow = value == 0x7F_u8
        set_zsp8(result)
        result
      end

      private def decrement16(value : UInt16) : UInt16
        result = value &- 1_u16
        @flags.auxiliary_carry = (value & 0x000F_u16) == 0_u16
        @flags.overflow = value == 0x8000_u16
        set_zsp16(result)
        result
      end

      private def decrement8(value : UInt8) : UInt8
        result = value &- 1_u8
        @flags.auxiliary_carry = (value & 0x0F_u8) == 0_u8
        @flags.overflow = value == 0x80_u8
        set_zsp8(result)
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

      private def execute_movsb(bus : MemoryBus) : UInt32
        iterations = @repeat_prefix ? @registers.cx : 1_u16
        return 1_u32 if iterations == 0_u16

        source_segment = @segment_override || @registers.ds
        iterations.times do
          value = bus.read_u8(Core.linear_address(source_segment, @registers.si))
          bus.write_u8(Core.linear_address(@registers.es, @registers.di), value)
          delta = @flags.direction ? 0xFFFF_u16 : 1_u16
          @registers.si &+= delta
          @registers.di &+= delta
        end
        @registers.cx = 0_u16 if @repeat_prefix
        5_u32 * iterations.to_u32
      end

      private def execute_string(bus : MemoryBus, opcode : UInt8) : UInt32
        iterations = @repeat_prefix ? @registers.cx : 1_u16
        return 0_u32 if iterations == 0_u16

        source_segment = @segment_override || @registers.ds
        total_cycles = 0_u32
        iterations.times do
          string_step(bus, opcode, source_segment)
          total_cycles += string_cycles(opcode)
          if @repeat_prefix
            @registers.cx &-= 1_u16
            if string_comparison?(opcode)
              break if @repeat_prefix == 0xF3_u8 && !@flags.zero
              break if @repeat_prefix == 0xF2_u8 && @flags.zero
            end
          end
        end
        total_cycles
      end

      private def string_step(bus : MemoryBus, opcode : UInt8, source_segment : UInt16) : Nil
        wide = opcode.bit(0) == 1
        delta = @flags.direction ? (wide ? 0xFFFE_u16 : 0xFFFF_u16) : (wide ? 2_u16 : 1_u16)
        source_address = Core.linear_address(source_segment, @registers.si)
        destination_address = Core.linear_address(@registers.es, @registers.di)

        case opcode
        when 0x6C_u8
          bus.write_u8(destination_address, bus.read_io(@registers.reg8(2_u8)))
          @registers.di &+= delta
        when 0x6D_u8
          port = @registers.reg8(2_u8)
          value = bus.read_io(port).to_u16 | (bus.read_io(port &+ 1_u8).to_u16 << 8)
          bus.write_u16(destination_address, value)
          @registers.di &+= delta
        when 0x6E_u8
          bus.write_io(@registers.reg8(2_u8), bus.read_u8(source_address))
          @registers.si &+= delta
        when 0x6F_u8
          port = @registers.reg8(2_u8)
          value = bus.read_u16(source_address)
          bus.write_io(port, (value & 0x00FF_u16).to_u8)
          bus.write_io(port &+ 1_u8, (value >> 8).to_u8)
          @registers.si &+= delta
        when 0xA4_u8
          bus.write_u8(destination_address, bus.read_u8(source_address))
          @registers.si &+= delta; @registers.di &+= delta
        when 0xA5_u8
          bus.write_u16(destination_address, bus.read_u16(source_address))
          @registers.si &+= delta; @registers.di &+= delta
        when 0xA6_u8
          subtract8(bus.read_u8(source_address), bus.read_u8(destination_address), 0_u8)
          @registers.si &+= delta; @registers.di &+= delta
        when 0xA7_u8
          subtract16(bus.read_u16(source_address), bus.read_u16(destination_address), 0_u16)
          @registers.si &+= delta; @registers.di &+= delta
        when 0xAA_u8
          bus.write_u8(destination_address, @registers.reg8(0_u8))
          @registers.di &+= delta
        when 0xAB_u8
          bus.write_u16(destination_address, @registers.ax)
          @registers.di &+= delta
        when 0xAC_u8
          @registers.set_reg8(0_u8, bus.read_u8(source_address))
          @registers.si &+= delta
        when 0xAD_u8
          @registers.ax = bus.read_u16(source_address)
          @registers.si &+= delta
        when 0xAE_u8
          subtract8(@registers.reg8(0_u8), bus.read_u8(destination_address), 0_u8)
          @registers.di &+= delta
        when 0xAF_u8
          subtract16(@registers.ax, bus.read_u16(destination_address), 0_u16)
          @registers.di &+= delta
        end
      end

      private def string_cycles(opcode : UInt8) : UInt32
        case opcode
        when 0x6C_u8, 0x6D_u8                   then 6_u32
        when 0x6E_u8, 0x6F_u8                   then 7_u32
        when 0xA4_u8, 0xA5_u8                   then 5_u32
        when 0xA6_u8, 0xA7_u8                   then 6_u32
        when 0xAA_u8, 0xAB_u8, 0xAC_u8, 0xAD_u8 then 3_u32
        else                                         4_u32
        end
      end

      private def string_comparison?(opcode : UInt8) : Bool
        opcode == 0xA6_u8 || opcode == 0xA7_u8 || opcode == 0xAE_u8 || opcode == 0xAF_u8
      end

      private def execute_stosb(bus : MemoryBus) : UInt32
        iterations = @repeat_prefix ? @registers.cx : 1_u16
        return 1_u32 if iterations == 0_u16

        delta = @flags.direction ? 0xFFFF_u16 : 1_u16
        iterations.times do
          bus.write_u8(Core.linear_address(@registers.es, @registers.di), @registers.reg8(0_u8))
          @registers.di &+= delta
        end
        @registers.cx = 0_u16 if @repeat_prefix
        3_u32 * iterations.to_u32
      end

      private def execute_lodsb(bus : MemoryBus) : UInt32
        iterations = @repeat_prefix ? @registers.cx : 1_u16
        return 1_u32 if iterations == 0_u16

        segment = @segment_override || @registers.ds
        delta = @flags.direction ? 0xFFFF_u16 : 1_u16
        iterations.times do
          @registers.set_reg8(0_u8, bus.read_u8(Core.linear_address(segment, @registers.si)))
          @registers.si &+= delta
        end
        @registers.cx = 0_u16 if @repeat_prefix
        3_u32 * iterations.to_u32
      end
    end
  end
end
