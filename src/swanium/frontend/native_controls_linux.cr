require "./linux_menu"
require "../platform/state_store"
require "./input_bindings"

module Swanium::Frontend
  # GTK3 adapter: only product actions cross this boundary. GTK ownership and
  # event dispatch remain in linux_menu.c.
  class NativeControls
    @volume : Int32
    getter quit_requested : Bool

    def self.start(title : String) : NativeControls
      if backend = ENV["GDK_BACKEND"]?
        raise Platform::SdlError.new("Linux native Wayland is not supported; use the GTK3 X11 backend through X11 or XWayland") unless backend.split(',').includes?("x11")
      end
      if driver = ENV["SDL_VIDEODRIVER"]?
        raise Platform::SdlError.new("Linux native Wayland is not supported; use the SDL2 x11 video driver through X11 or XWayland") unless driver.split(',').includes?("x11")
      end
      ENV["GDK_BACKEND"] = "x11"
      ENV["SDL_VIDEODRIVER"] = "x11"
      new(title)
    end

    def initialize(@title : String)
      @quit_requested = false; @pause_requested = false; @reset_requested = false
      @open_rom_path = nil.as(String?); @save_state_requested = nil.as(Int32?); @load_state_requested = nil.as(Int32?)
      @scale_requested = nil.as(Int32?); @fullscreen_requested = false; @renderer_requested = nil.as(Int32?)
      @keyboard_capture = nil.as(Int32?); @controller_capture = nil.as(Int32?)
      @settings_snapshot = nil.as(Hash(String, String)?)
      @volume = Platform::StateStore.default.settings["volume"]?.try(&.to_i?).try(&.clamp(0, 100)) || 100
    end

    def install_menus(width : Int32, height : Int32, x : Int32, y : Int32) : Void*
      handle = LinuxMenu.build(@title, @volume, initial_scale, width, height, x, y)
      raise Platform::SdlError.new(LinuxMenu.error_text) if handle.null?
      LinuxMenu.recent = Platform::StateStore.default.recent_roms
      handle
    end

    def pump : Nil
      LinuxMenu.pump
      case action = LinuxMenu.take_action
      when LinuxMenu::OPEN_ROM                                  then @open_rom_path = LinuxMenu.open_rom
      when LinuxMenu::RECENT_BASE..(LinuxMenu::RECENT_BASE + 9) then @open_rom_path = LinuxMenu.recent_path(action - LinuxMenu::RECENT_BASE)
      when LinuxMenu::CLEAR_RECENT
        Platform::StateStore.default.clear_recent_roms
        LinuxMenu.recent = [] of String
      when LinuxMenu::QUIT                                              then @quit_requested = true
      when LinuxMenu::PAUSE                                             then @pause_requested = true
      when LinuxMenu::RESET                                             then @reset_requested = true
      when LinuxMenu::SAVE_STATE_BASE..(LinuxMenu::SAVE_STATE_BASE + 9) then @save_state_requested = action - LinuxMenu::SAVE_STATE_BASE
      when LinuxMenu::LOAD_STATE_BASE..(LinuxMenu::LOAD_STATE_BASE + 9) then @load_state_requested = action - LinuxMenu::LOAD_STATE_BASE
      when LinuxMenu::SCALE_1..LinuxMenu::SCALE_4
        @scale_requested = action - LinuxMenu::SCALE_1 + 1
      when LinuxMenu::FULLSCREEN     then @fullscreen_requested = true
      when LinuxMenu::RENDER_NEAREST then @renderer_requested = 0
      when LinuxMenu::RENDER_LINEAR  then @renderer_requested = 1
      when LinuxMenu::ABOUT          then LinuxMenu.about
      when LinuxMenu::SETTINGS
        @settings_snapshot = Platform::StateStore.default.settings.dup
        LinuxMenu.settings
        sync_settings
      when 400..410 then @keyboard_capture = action - 400
      when 500..502 then @controller_capture = action - 500
      when 420      then InputBindings.default.reset_keyboard; @keyboard_capture = nil; sync_settings
      when 520      then InputBindings.default.reset_controller; @controller_capture = nil; sync_settings
      when 530      then @settings_snapshot = nil
      when 531      then restore_settings_snapshot
      when 6000..6022
        source = action // 10 - 600; destination = action % 10
        key = ["dpad", "left_stick", "right_stick"][source]?
        InputBindings.default.set_controller_destination(key, destination) if key && destination.in?(0..2)
        sync_settings
      when 7000..7999
        capture_keyboard(action - 7000)
      end
    end

    def take_pause_request? : Bool
      value = @pause_requested; @pause_requested = false; value
    end

    def take_open_rom_path : String?
      value = @open_rom_path; @open_rom_path = nil; value
    end

    def take_save_state_request : Int32?
      value = @save_state_requested; @save_state_requested = nil; value
    end

    def take_load_state_request : Int32?
      value = @load_state_requested; @load_state_requested = nil; value
    end

    def take_reset_request? : Bool
      value = @reset_requested; @reset_requested = false; value
    end

    def take_scale_request : Int32?
      value = @scale_requested; @scale_requested = nil; value
    end

    def take_fullscreen_request? : Bool
      value = @fullscreen_requested; @fullscreen_requested = false; value
    end

    def take_renderer_request : Int32?
      value = @renderer_requested; @renderer_requested = nil; value
    end

    def initial_scale : Int32
      Platform::StateStore.default.settings["scale"]?.try(&.to_i?).try(&.clamp(1, 4)) || 3
    end

    def save_scale(scale : Int32) : Nil
      values = Platform::StateStore.default.settings; values["scale"] = scale.to_s; Platform::StateStore.default.save_settings(values)
    end

    def update_status(title : String, fps : Float64, paused : Bool) : Nil
      LinuxMenu.status(title, paused ? "paused" : "#{fps.round.to_i} fps")
    end

    def update_menu_state(paused : Bool, scale : Int32, fullscreen : Bool, renderer : Int32) : Nil
      LinuxMenu.state(paused, scale, fullscreen, renderer)
    end

    def update_state_slots(rom_id : String) : Nil
      store = Platform::StateStore.default
      LinuxMenu.state_slots = {store.state_slot_labels(rom_id), 10.times.map { |slot| store.state_exists?(rom_id, slot) }.to_a}
    end

    def show_error(message : String) : Nil
      LinuxMenu.error(message)
    end

    def attach_status(window : Void*) : Nil; end

    def detach_status : Nil; end

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
      value = LinuxMenu.volume
      if value != @volume
        @volume = value; settings = Platform::StateStore.default.settings; settings["volume"] = value.to_s; Platform::StateStore.default.save_settings(settings)
      end
      value
    end

    def reserved_status_height(window : Void*) : Int32
      0
    end

    def resize_game(width : Int32, height : Int32, scale : Int32) : Nil
      LinuxMenu.resize_game(width, height, scale)
    end

    def close : Nil
      LinuxMenu.destroy
    end

    private def sync_settings : Nil
      bindings = InputBindings.default
      keyboard = InputBindings::ACTIONS.map { |action| InputBindings.option_name(bindings.scancode(action)) }
      buttons = [:a, :b, :start].map { |action| InputBindings.controller_button_name(bindings.controller_button(action)) }
      directions = [bindings.controller_destination("dpad", 1), bindings.controller_destination("left_stick", 1), bindings.controller_destination("right_stick", 2)]
      LinuxMenu.settings_sync(keyboard, buttons, directions)
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
      store.save_settings(snapshot)
      @keyboard_capture = nil
      @controller_capture = nil
      @settings_snapshot = nil
    end
  end
end
