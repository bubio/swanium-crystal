module Swanium
  module Core
    # Optional cartridge RTC. The core never reads wall-clock time: the device
    # starts from a fixed epoch and advances only from emulated master cycles.
    class Rtc
      CYCLES_PER_SECOND = 3_072_000_u32
      OPEN_BUS          =       0x90_u8

      private CMD_READY = 0x80_u8
      private CMD_BUSY  = 0x10_u8
      private CMD_MASK  = 0x1F_u8

      @year : UInt8
      @month : UInt8
      @day : UInt8
      @weekday : UInt8
      @hour : UInt8
      @minute : UInt8
      @second : UInt8
      @status : UInt8
      @alarm_hour : UInt8
      @alarm_minute : UInt8
      @command : UInt8
      @index : UInt8
      @remaining : UInt8
      @unsupported_busy : Bool
      @cycle_accumulator : UInt32

      def initialize
        @year = 0x00_u8
        @month = 0x01_u8
        @day = 0x01_u8
        @weekday = 6_u8
        @hour = 0x00_u8
        @minute = 0x00_u8
        @second = 0x00_u8
        @status = 0_u8
        @alarm_hour = 0_u8
        @alarm_minute = 0_u8
        @command = 0_u8
        @index = 0_u8
        @remaining = 0_u8
        @unsupported_busy = false
        @cycle_accumulator = 0_u32
      end

      def tick(cycles : UInt32) : Nil
        @cycle_accumulator += cycles
        while @cycle_accumulator >= CYCLES_PER_SECOND
          @cycle_accumulator -= CYCLES_PER_SECOND
          advance_second
        end
      end

      def write_command(value : UInt8) : Nil
        @command = value
        @index = 0_u8
        if (value & CMD_READY) != 0_u8
          @remaining = 0_u8
          @unsupported_busy = false
          return
        end

        command = value & CMD_MASK
        @remaining = transfer_length(command)
        @unsupported_busy = @remaining == 0_u8
        reset_registers if command == 0x10_u8
      end

      def read_command : UInt8
        ready = @remaining > 0_u8 ? CMD_READY : 0_u8
        busy = (@remaining > 1_u8 || @unsupported_busy) ? CMD_BUSY : 0_u8
        ready | busy
      end

      def write_data(value : UInt8) : Nil
        case @command & CMD_MASK
        when 0x14_u8, 0x15_u8
          set_datetime_byte(@index, value)
          @index = (@index + 1_u8) % 7_u8
          consume_transfer_byte
        when 0x18_u8, 0x1A_u8
          if @index == 0_u8
            @alarm_hour = value
          else
            @alarm_minute = value
          end
          @index = (@index + 1_u8) % 2_u8
          consume_transfer_byte
        when 0x12_u8, 0x13_u8
          @status = value
          consume_transfer_byte
        when 0x16_u8, 0x17_u8
          consume_transfer_byte
        end
      end

      def read_data : UInt8
        case @command & CMD_MASK
        when 0x14_u8, 0x15_u8
          value = datetime_byte(@index)
          @index = (@index + 1_u8) % 7_u8
          consume_transfer_byte
          value
        when 0x19_u8, 0x1B_u8
          value = @index == 0_u8 ? @alarm_hour : @alarm_minute
          @index = (@index + 1_u8) % 2_u8
          consume_transfer_byte
          value
        when 0x12_u8, 0x13_u8
          consume_transfer_byte
          @status
        when 0x16_u8, 0x17_u8
          consume_transfer_byte
          0_u8
        else
          OPEN_BUS
        end
      end

      # Decimal input keeps the platform boundary explicit while the device
      # itself stores the same packed-BCD registers exposed to guest code.
      def set_datetime(year : UInt8, month : UInt8, day : UInt8, weekday : UInt8,
                       hour : UInt8, minute : UInt8, second : UInt8) : Nil
        @year = to_bcd(year % 100_u8)
        @month = to_bcd(month.clamp(1_u8, 12_u8))
        @day = to_bcd(day.clamp(1_u8, 31_u8))
        @weekday = weekday % 7_u8
        @hour = to_bcd(hour.clamp(0_u8, 23_u8))
        @minute = to_bcd(minute.clamp(0_u8, 59_u8))
        @second = to_bcd(second.clamp(0_u8, 59_u8))
        @cycle_accumulator = 0_u32
      end

      def save_state(io : IO) : Nil
        {@year, @month, @day, @weekday, @hour, @minute, @second, @status, @alarm_hour, @alarm_minute,
         @command, @index, @remaining, @unsupported_busy ? 1_u8 : 0_u8}.each { |value| io.write_byte(value) }
        io.write_bytes(@cycle_accumulator, IO::ByteFormat::LittleEndian)
      end

      def load_state(io : IO) : Nil
        @year = read_byte(io); @month = read_byte(io); @day = read_byte(io); @weekday = read_byte(io) & 0x07_u8
        @hour = read_byte(io); @minute = read_byte(io); @second = read_byte(io); @status = read_byte(io)
        @alarm_hour = read_byte(io); @alarm_minute = read_byte(io); @command = read_byte(io); @index = read_byte(io)
        @remaining = read_byte(io); @unsupported_busy = read_byte(io) != 0_u8
        @cycle_accumulator = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
      end

      private def reset_registers : Nil
        @year = 0x00_u8; @month = 0x01_u8; @day = 0x01_u8; @weekday = 6_u8
        @hour = 0x00_u8; @minute = 0x00_u8; @second = 0x00_u8; @status = 0_u8
        @alarm_hour = 0_u8; @alarm_minute = 0_u8
      end

      private def advance_second : Nil
        second = from_bcd(@second) + 1
        if second < 60
          @second = to_bcd(second)
          return
        end
        @second = 0_u8
        minute = from_bcd(@minute) + 1
        if minute < 60
          @minute = to_bcd(minute)
          return
        end
        @minute = 0_u8
        hour = from_bcd(@hour) + 1
        if hour < 24
          @hour = to_bcd(hour)
          return
        end
        @hour = 0_u8
        @weekday = (@weekday + 1_u8) % 7_u8
        year = from_bcd(@year)
        month = from_bcd(@month)
        day = from_bcd(@day) + 1
        if day <= days_in_month(month, year)
          @day = to_bcd(day)
          return
        end
        @day = 0x01_u8
        month += 1
        if month <= 12
          @month = to_bcd(month)
          return
        end
        @month = 0x01_u8
        @year = to_bcd((year + 1) % 100)
      end

      private def datetime_byte(index : UInt8) : UInt8
        case index
        when 0_u8 then @year
        when 1_u8 then @month
        when 2_u8 then @day
        when 3_u8 then @weekday
        when 4_u8 then @hour
        when 5_u8 then @minute
        else           @second
        end
      end

      private def set_datetime_byte(index : UInt8, value : UInt8) : Nil
        case index
        when 0_u8 then @year = value
        when 1_u8 then @month = value
        when 2_u8 then @day = value
        when 3_u8 then @weekday = value & 0x07_u8
        when 4_u8 then @hour = value
        when 5_u8 then @minute = value
        else           @second = value
        end
      end

      private def consume_transfer_byte : Nil
        @remaining -= 1_u8 if @remaining > 0_u8
      end

      private def transfer_length(command : UInt8) : UInt8
        case command
        when 0x10_u8..0x13_u8 then 1_u8
        when 0x14_u8, 0x15_u8 then 7_u8
        when 0x16_u8, 0x17_u8 then 3_u8
        when 0x18_u8..0x1B_u8 then 2_u8
        else                       0_u8
        end
      end

      private def to_bcd(value : UInt8) : UInt8
        ((value // 10_u8) << 4) | (value % 10_u8)
      end

      private def from_bcd(value : UInt8) : UInt8
        (value >> 4) * 10_u8 + (value & 0x0F_u8)
      end

      private def days_in_month(month : UInt8, year : UInt8) : UInt8
        case month
        when 1_u8, 3_u8, 5_u8, 7_u8, 8_u8, 10_u8, 12_u8 then 31_u8
        when 4_u8, 6_u8, 9_u8, 11_u8                    then 30_u8
        when 2_u8                                       then year % 4_u8 == 0_u8 ? 29_u8 : 28_u8
        else                                                 30_u8
        end
      end

      private def read_byte(io : IO) : UInt8
        io.read_byte || raise IO::EOFError.new
      end
    end
  end
end
