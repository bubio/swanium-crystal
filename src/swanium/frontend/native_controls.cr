require "uing"

module Swanium
  module Frontend
    # Native controls are deliberately kept outside SDL. SDL continues to
    # own the low-latency screen, keyboard/gamepad, and audio paths, while
    # libui-ng/AppKit supplies accessible text, menus, and sliders.
    class NativeControls
      getter volume : Int32
      getter quit_requested : Bool

      def self.start(title : String) : NativeControls
        UIng.init
        new(title)
      end

      def initialize(title : String)
        @volume = 100
        @quit_requested = false
        @pause_requested = false
        @save_state_requested = false
        @load_state_requested = false
        @open_rom_path = nil.as(String?)

        file = UIng::Menu.new("File")
        file.append_item("Open ROM…").on_clicked do |window|
          @open_rom_path = window.open_file
        end
        file.append_separator
        file.append_item("Save State").on_clicked { |_| @save_state_requested = true }
        file.append_item("Load State").on_clicked { |_| @load_state_requested = true }
        file.append_separator
        file.append_quit_item.on_clicked { |_| @quit_requested = true }
        emulation = UIng::Menu.new("Emulation")
        emulation.append_item("Pause / Resume").on_clicked { |_| @pause_requested = true }

        @status = UIng::Label.new("#{title} — starting…")
        @volume_label = UIng::Label.new("Volume: 100%")
        slider = UIng::Slider.new(0, 100, @volume)
        slider.on_changed do |value|
          @volume = value.clamp(0, 100)
          @volume_label.text = "Volume: #{@volume}%"
        end
        controls = UIng::Box.new(:vertical, padded: true)
        controls.append(@status)
        controls.append(@volume_label)
        controls.append(slider)

        @window = UIng::Window.new("Swanium Crystal", 360, 110, menubar: true, margined: true)
        @window.child = controls
        @window.on_closing do
          # Destruction from inside libui's close delegate is unsafe on
          # macOS. The owning frontend performs it after its loop unwinds.
          @quit_requested = true
          false
        end
        @window.show
        UIng.main_steps
      end

      def pump : Nil
        UIng.main_step(false)
      end

      def take_pause_request? : Bool
        requested = @pause_requested
        @pause_requested = false
        requested
      end

      def take_open_rom_path : String?
        path = @open_rom_path
        @open_rom_path = nil
        path
      end

      def take_save_state_request? : Bool
        requested = @save_state_requested
        @save_state_requested = false
        requested
      end

      def take_load_state_request? : Bool
        requested = @load_state_requested
        @load_state_requested = false
        requested
      end

      def update_status(title : String, fps : Float64, paused : Bool) : Nil
        suffix = paused ? "paused" : "#{fps.round.to_i} fps"
        @status.text = "#{title} — #{suffix}"
      end

      def close : Nil
        @window.destroy unless @window.released?
        UIng.uninit
      end
    end
  end
end
