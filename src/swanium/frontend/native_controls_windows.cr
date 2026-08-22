require "./windows_menu"
require "../platform/state_store"
require "./input_bindings"

module Swanium::Frontend
  # Win32 adapter with the same product-action boundary as the Linux GTK UI.
  class NativeControls
    @volume : Int32
    getter quit_requested : Bool

    def self.start(title : String) : NativeControls; new(title); end

    def initialize(@title : String)
      @quit_requested = false; @pause_requested = false; @reset_requested = false
      @open_rom_path = nil.as(String?); @save_state_requested = nil.as(Int32?); @load_state_requested = nil.as(Int32?)
      @scale_requested = nil.as(Int32?); @fullscreen_requested = false; @renderer_requested = nil.as(Int32?)
      @keyboard_capture = nil.as(Int32?); @controller_capture = nil.as(Int32?)
      @settings_snapshot = nil.as(Hash(String, String)?)
      @volume = saved_volume
    end

    def install_menus : Nil
      raise Platform::SdlError.new("Could not attach the Windows menu") unless WindowsMenu.attach(@title, @volume, initial_scale)
      WindowsMenu.recent = Platform::StateStore.default.recent_roms
    end

    def refresh_recent_roms : Nil; WindowsMenu.recent = Platform::StateStore.default.recent_roms; end

    def pump : Nil
      WindowsMenu.pump
      case action = WindowsMenu.take_action
      when WindowsMenu::OPEN_ROM then @open_rom_path = WindowsMenu.open_rom
      when WindowsMenu::RECENT_BASE..(WindowsMenu::RECENT_BASE + 9) then @open_rom_path = WindowsMenu.recent_path(action - WindowsMenu::RECENT_BASE)
      when WindowsMenu::CLEAR_RECENT
        Platform::StateStore.default.clear_recent_roms; WindowsMenu.recent = [] of String
      when WindowsMenu::QUIT then @quit_requested = true
      when WindowsMenu::PAUSE then @pause_requested = true
      when WindowsMenu::RESET then @reset_requested = true
      when WindowsMenu::SAVE_STATE_BASE..(WindowsMenu::SAVE_STATE_BASE + 9) then @save_state_requested = action - WindowsMenu::SAVE_STATE_BASE
      when WindowsMenu::LOAD_STATE_BASE..(WindowsMenu::LOAD_STATE_BASE + 9) then @load_state_requested = action - WindowsMenu::LOAD_STATE_BASE
      when WindowsMenu::SCALE_1..WindowsMenu::SCALE_4 then @scale_requested = action - WindowsMenu::SCALE_1 + 1
      when WindowsMenu::FULLSCREEN then @fullscreen_requested = true
      when WindowsMenu::RENDER_NEAREST then @renderer_requested = 0
      when WindowsMenu::RENDER_LINEAR then @renderer_requested = 1
      when WindowsMenu::ABOUT then WindowsMenu.about
      when WindowsMenu::SETTINGS
        @settings_snapshot = Platform::StateStore.default.settings.dup
        WindowsMenu.settings; sync_settings
      when 400..410 then @keyboard_capture = action - 400
      when 500..502 then @controller_capture = action - 500
      when 420 then InputBindings.default.reset_keyboard; @keyboard_capture = nil; sync_settings
      when 520 then InputBindings.default.reset_controller; @controller_capture = nil; sync_settings
      when 530 then @settings_snapshot = nil
      when 531 then restore_settings_snapshot
      when 6000..6022
        source = action // 10 - 600; destination = action % 10
        key = ["dpad", "left_stick", "right_stick"][source]?
        InputBindings.default.set_controller_destination(key, destination) if key && destination.in?(0..2)
        sync_settings
      when 7000..7999
        capture_keyboard(action - 7000)
      end
    end

    def take_pause_request? : Bool; value = @pause_requested; @pause_requested = false; value; end
    def take_open_rom_path : String?; value = @open_rom_path; @open_rom_path = nil; value; end
    def take_save_state_request : Int32?; value = @save_state_requested; @save_state_requested = nil; value; end
    def take_load_state_request : Int32?; value = @load_state_requested; @load_state_requested = nil; value; end
    def take_reset_request? : Bool; value = @reset_requested; @reset_requested = false; value; end
    def take_scale_request : Int32?; value = @scale_requested; @scale_requested = nil; value; end
    def take_fullscreen_request? : Bool; value = @fullscreen_requested; @fullscreen_requested = false; value; end
    def take_renderer_request : Int32?; value = @renderer_requested; @renderer_requested = nil; value; end
    def initial_scale : Int32; Platform::StateStore.default.settings["scale"]?.try(&.to_i?).try(&.clamp(1, 4)) || 3; end
    def save_scale(scale : Int32) : Nil
      settings = Platform::StateStore.default.settings; settings["scale"] = scale.clamp(1, 4).to_s; Platform::StateStore.default.save_settings(settings)
    end
    def update_status(title : String, fps : Float64, paused : Bool) : Nil
      WindowsMenu.status(title, paused ? "paused" : "#{fps.round.to_i} fps")
    end
    def update_menu_state(paused : Bool, scale : Int32, fullscreen : Bool, renderer : Int32) : Nil
      WindowsMenu.state(paused, scale, fullscreen, renderer)
    end
    def update_state_slots(rom_id : String) : Nil
      store = Platform::StateStore.default
      WindowsMenu.state_slots = {store.state_slot_labels(rom_id), 10.times.map { |slot| store.state_exists?(rom_id, slot) }.to_a}
    end
    def show_error(message : String) : Nil; WindowsMenu.error(message); end
    def attach_status(window : Void*) : Nil; WindowsMenu.attach_status; end
    def detach_status : Nil; end
    def reserved_status_height(window : Void*) : Int32; WindowsMenu.status_height; end
    def capture_keyboard(scancode : Int32) : Bool
      return false unless action = @keyboard_capture
      InputBindings.default.set(InputBindings::ACTIONS[action], scancode) unless scancode == 41
      @keyboard_capture = nil; sync_settings; true
    end
    def capture_controller_button(button : Int32) : Bool
      return false unless action = @controller_capture
      InputBindings.default.set_controller_button([:a, :b, :start][action], button)
      @controller_capture = nil; sync_settings; true
    end
    def volume : Int32
      value = WindowsMenu.volume
      if value != @volume
        @volume = value; settings = Platform::StateStore.default.settings; settings["volume"] = value.to_s; Platform::StateStore.default.save_settings(settings)
      end
      value
    end
    def close : Nil; WindowsMenu.destroy; end

    private def saved_volume : Int32
      Platform::StateStore.default.settings["volume"]?.try(&.to_i?).try(&.clamp(0, 100)) || 100
    end
    private def sync_settings : Nil
      bindings = InputBindings.default
      keyboard = InputBindings::ACTIONS.map { |action| InputBindings.option_name(bindings.scancode(action)) }
      buttons = [:a, :b, :start].map { |action| InputBindings.controller_button_name(bindings.controller_button(action)) }
      directions = [bindings.controller_destination("dpad", 1), bindings.controller_destination("left_stick", 1), bindings.controller_destination("right_stick", 2)]
      WindowsMenu.settings_sync(keyboard, buttons, directions)
    end

    private def restore_settings_snapshot : Nil
      return unless snapshot = @settings_snapshot
      store = Platform::StateStore.default
      store.save_settings(snapshot)
      bindings = InputBindings.default
      InputBindings::ACTIONS.each do |input_action|
        value = snapshot["binding.#{input_action}"]?.try(&.to_i?) || InputBindings::DEFAULTS[input_action]
        bindings.set(input_action, value)
      end
      @keyboard_capture = nil
      @controller_capture = nil
      @settings_snapshot = nil
    end
  end
end
