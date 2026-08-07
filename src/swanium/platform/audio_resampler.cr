module Swanium
  module Platform
    # Stateful linear stereo resampler. Its phase crosses video-frame
    # boundaries so host-rate conversion never introduces frame-edge clicks.
    class AudioResampler
      getter output_rate : Int32

      def initialize(@input_rate : Int32, @output_rate : Int32)
        raise ArgumentError.new("audio sample rates must be positive") if @input_rate <= 0 || @output_rate <= 0
        @phase = 0_i64
        @previous_left = 0_i16
        @previous_right = 0_i16
        @has_previous = false
        @output = [] of Int16
      end

      def process(input : Array(Int16)) : Array(Int16)
        @output.clear
        if @input_rate == @output_rate
          @output.concat(input)
          return @output
        end

        index = 0
        while index + 1 < input.size
          left = input[index]
          right = input[index + 1]
          unless @has_previous
            @output << left << right
            @previous_left = left
            @previous_right = right
            @has_previous = true
            @phase = @input_rate.to_i64
            index += 2
            next
          end
          while @phase <= @output_rate
            @output << interpolate(@previous_left, left, @phase, @output_rate)
            @output << interpolate(@previous_right, right, @phase, @output_rate)
            @phase += @input_rate.to_i64
          end
          @phase -= @output_rate.to_i64
          @previous_left = left
          @previous_right = right
          index += 2
        end
        @output
      end

      private def interpolate(before : Int16, after : Int16, numerator : Int64, denominator : Int32) : Int16
        before_i = before.to_i32
        (before_i + (after.to_i32 - before_i) * numerator // denominator).to_i16
      end
    end
  end
end
