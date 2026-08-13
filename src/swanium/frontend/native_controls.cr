require "./macos_menu"
require "../platform/state_store"
require "./input_bindings"

module Swanium
  module Frontend
    # Native controls are deliberately kept outside SDL. SDL continues to
    # own the low-latency screen, keyboard/gamepad, and audio paths, while
    # libui-ng/AppKit supplies the application menu and native status bar.
    class NativeControls
      @volume : Int32

      getter quit_requested : Bool

      def self.start(title : String) : NativeControls
        new(title)
      end

      def initialize(title : String)
        @quit_requested = false
        @pause_requested = false
        @save_state_requested = nil.as(Int32?)
        @load_state_requested = nil.as(Int32?)
        @open_rom_path = nil.as(String?)
        @keyboard_capture = nil.as(Int32?)
        @controller_capture = nil.as(Int32?)
        @reset_requested = false
        @scale_requested = nil.as(Int32?)
        @fullscreen_requested = false
        @renderer_requested = nil.as(Int32?)
        @volume = saved_volume
      end

      def install_menus : Nil
        MacosMenu.install
        MacosMenu.set_recent_roms(Platform::StateStore.default.recent_roms)
      end

      def pump : Nil
        action = MacosMenu.take_action
        case action
        when MacosMenu::OPEN_ROM
          @open_rom_path = MacosMenu.open_rom
        when MacosMenu::RECENT_BASE..(MacosMenu::RECENT_BASE + 9)
          @open_rom_path = MacosMenu.recent_rom(action - MacosMenu::RECENT_BASE)
        when MacosMenu::CLEAR_RECENT
          Platform::StateStore.default.clear_recent_roms
          MacosMenu.set_recent_roms([] of String)
        when MacosMenu::ABOUT
          MacosMenu.show_about
        when MacosMenu::SETTINGS
          show_settings
        when 400..410
          @keyboard_capture = action - 400
        when 500..502
          @controller_capture = action - 500
        when 420
          InputBindings.default.reset_keyboard
          @keyboard_capture = nil
          sync_settings
        when 520
          InputBindings.default.reset_controller
          @controller_capture = nil
          sync_settings
        when 6000..6022
          source = action // 10 - 600
          destination = action % 10
          key = ["dpad", "left_stick", "right_stick"][source]?
          InputBindings.default.set_controller_destination(key, destination) if key && destination.in?(0..2)
          sync_settings
        when 7000..7999
          capture_keyboard(action - 7000)
        when MacosMenu::QUIT
          @quit_requested = true
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

      def initial_scale : Int32
        Platform::StateStore.default.settings["scale"]?.try(&.to_i?).try(&.clamp(1, 4)) || 3
      end

      def save_scale(scale : Int32) : Nil
        settings = Platform::StateStore.default.settings
        settings["scale"] = scale.clamp(1, 4).to_s
        Platform::StateStore.default.save_settings(settings)
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
        MacosMenu.update_status("#{title} — #{suffix}")
      end

      def update_menu_state(paused : Bool, scale : Int32, fullscreen : Bool, renderer : Int32) : Nil
        MacosMenu.update_menu_state(paused, scale, fullscreen, renderer)
      end

      def update_state_slots(rom_id : String) : Nil
        store = Platform::StateStore.default
        slots = 10.times.map { |slot| store.state_exists?(rom_id, slot) }.to_a
        MacosMenu.set_state_slots(store.state_slot_labels(rom_id), slots)
      end

      def show_error(message : String) : Nil
        MacosMenu.show_error(message)
      end

      def attach_status(window : Void*) : Nil
        MacosMenu.attach_status(window)
        MacosMenu.volume = @volume
        sync_settings
      end

      def detach_status : Nil
        MacosMenu.detach_status
      end

      def capture_keyboard(scancode : Int32) : Bool
        if scancode == 41 && (@keyboard_capture || @controller_capture)
          @keyboard_capture = nil
          @controller_capture = nil
          sync_settings
          return true
        end
        action = @keyboard_capture
        return false unless action
        InputBindings.default.set(InputBindings::ACTIONS[action], scancode)
        @keyboard_capture = nil
        sync_settings
        true
      end

      def capture_controller_button(button : Int32) : Bool
        action = @controller_capture
        return false unless action
        InputBindings.default.set_controller_button([:a, :b, :start][action], button)
        @controller_capture = nil
        sync_settings
        true
      end

      def volume : Int32
        value = MacosMenu.volume
        if value != @volume
          @volume = value
          save_volume
        end
        value
      end

      def reserved_status_height(window : Void*) : Int32
        MacosMenu.reserved_status_height(window)
      end

      def close : Nil
      end

      private def show_settings : Nil
        MacosMenu.show_settings
        sync_settings
      end

      private def sync_settings : Nil
        bindings = InputBindings.default
        keyboard = InputBindings::ACTIONS.map { |action| InputBindings.option_name(bindings.scancode(action)) }
        buttons = [:a, :b, :start].map { |action| InputBindings.controller_button_name(bindings.controller_button(action)) }
        directions = [bindings.controller_destination("dpad", 1), bindings.controller_destination("left_stick", 1), bindings.controller_destination("right_stick", 2)]
        MacosMenu.sync_settings(keyboard, buttons, directions)
      end

      private def saved_volume : Int32
        Platform::StateStore.default.settings["volume"]?.try(&.to_i?).try(&.clamp(0, 100)) || 100
      end

      private def save_volume : Nil
        settings = Platform::StateStore.default.settings
        settings["volume"] = @volume.to_s
        Platform::StateStore.default.save_settings(settings)
      end
    end
  end
end
