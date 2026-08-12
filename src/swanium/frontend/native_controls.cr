require "uing"
require "./macos_menu"

module Swanium
  module Frontend
    # Native controls are deliberately kept outside SDL. SDL continues to
    # own the low-latency screen, keyboard/gamepad, and audio paths, while
    # libui-ng/AppKit supplies accessible text, menus, and sliders.
    class NativeControls
      getter quit_requested : Bool

      def self.start(title : String) : NativeControls
        UIng.init
        new(title)
      end

      def initialize(title : String)
        @volume = 100
        @quit_requested = false
        @pause_requested = false
        @save_state_requested = nil.as(Int32?)
        @load_state_requested = nil.as(Int32?)
        @open_rom_path = nil.as(String?)
        @settings_window = nil.as(UIng::Window?)
        @reset_requested = false
        @scale_requested = nil.as(Int32?)
        @fullscreen_requested = false
        @renderer_requested = nil.as(Int32?)

        application = UIng::Menu.new("Swanium Crystal")
        application.append_about_item.on_clicked do |window|
          window.msg_box("About Swanium Crystal", "WonderSwan and WonderSwan Color emulator.")
        end
        application.append_preferences_item.on_clicked { |_| show_settings }
        application.append_quit_item
        # libui-ng reserves Quit items for this global callback. Registering
        # uiMenuItemOnClicked on a Quit item terminates the process on macOS.
        UIng.on_should_quit do
          @quit_requested = true
          false
        end

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
        MacosMenu.install
        # libui-ng needs this host menu to create its application-menu items,
        # but the host itself must not remain as a second top-level menu.
        MacosMenu.hide_libui_menu
        UIng.main_steps
      end

      def pump : Nil
        UIng.main_step(false)
        action = MacosMenu.take_action
        case action
        when MacosMenu::OPEN_ROM
          @open_rom_path = @window.open_file
        when MacosMenu::SAVE_STATE_BASE..(MacosMenu::SAVE_STATE_BASE + 9)
          @save_state_requested = action - MacosMenu::SAVE_STATE_BASE
        when MacosMenu::LOAD_STATE_BASE..(MacosMenu::LOAD_STATE_BASE + 9)
          @load_state_requested = action - MacosMenu::LOAD_STATE_BASE
        when MacosMenu::PAUSE
          @pause_requested = true
        when MacosMenu::RESET
          @reset_requested = true
        when MacosMenu::SCALE_1
          @scale_requested = 1
        when MacosMenu::SCALE_2
          @scale_requested = 2
        when MacosMenu::SCALE_3
          @scale_requested = 3
        when MacosMenu::SCALE_4
          @scale_requested = 4
        when MacosMenu::FULLSCREEN
          @fullscreen_requested = true
        when MacosMenu::RENDER_NEAREST
          @renderer_requested = 0
        when MacosMenu::RENDER_LINEAR
          @renderer_requested = 1
        end
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

      def take_save_state_request : Int32?
        slot = @save_state_requested
        @save_state_requested = nil
        slot
      end

      def take_load_state_request : Int32?
        slot = @load_state_requested
        @load_state_requested = nil
        slot
      end

      def take_reset_request? : Bool
        requested = @reset_requested
        @reset_requested = false
        requested
      end

      def take_scale_request : Int32?
        scale = @scale_requested
        @scale_requested = nil
        scale
      end

      def take_fullscreen_request? : Bool
        requested = @fullscreen_requested
        @fullscreen_requested = false
        requested
      end

      def take_renderer_request : Int32?
        renderer = @renderer_requested
        @renderer_requested = nil
        renderer
      end

      def update_status(title : String, fps : Float64, paused : Bool) : Nil
        suffix = paused ? "paused" : "#{fps.round.to_i} fps"
        @status.text = "#{title} — #{suffix}"
        MacosMenu.update_status("#{title} — #{suffix}")
      end

      def attach_status(window : Void*) : Nil
        MacosMenu.attach_status(window)
      end

      def volume : Int32
        MacosMenu.volume
      end

      def close : Nil
        @settings_window.try do |window|
          window.destroy unless window.released?
        end
        @window.destroy unless @window.released?
        UIng.uninit
      end

      private def show_settings : Nil
        if window = @settings_window
          window.show
          return
        end

        bindings = UIng::Label.new("Input bindings\n\nX pad: Arrow keys\nY pad: W / A / S / D\nA / B: X / Z\nStart: Return")
        window = UIng::Window.new("Swanium Crystal Settings", 330, 180, margined: true)
        window.child = bindings
        window.on_closing do
          @settings_window = nil
          true
        end
        @settings_window = window
        window.show
      end
    end
  end
end
