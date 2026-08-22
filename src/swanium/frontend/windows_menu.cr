lib LibWindowsMenu
  fun attach = swanium_windows_menu_attach(title : LibC::Char*, volume : Int32, scale : Int32) : Int32
  fun pump = swanium_windows_menu_pump : Nil
  fun take_action = swanium_windows_menu_take_action : Int32
  fun open_rom = swanium_windows_menu_open_rom : LibC::Char*
  fun recent = swanium_windows_menu_recent(paths : LibC::Char**) : Nil
  fun recent_path = swanium_windows_menu_recent_path(index : Int32) : LibC::Char*
  fun state_slots = swanium_windows_menu_state_slots(labels : LibC::Char**, available : Int32*) : Nil
  fun status = swanium_windows_menu_status(title : LibC::Char*, fps : LibC::Char*) : Nil
  fun attach_status = swanium_windows_menu_attach_status : Nil
  fun status_height = swanium_windows_menu_status_height : Int32
  fun state = swanium_windows_menu_state(paused : Int32, scale : Int32, fullscreen : Int32, renderer : Int32) : Nil
  fun volume = swanium_windows_menu_volume : Int32
  fun error = swanium_windows_menu_error(text : LibC::Char*) : Nil
  fun about = swanium_windows_menu_about : Nil
  fun settings = swanium_windows_menu_settings : Nil
  fun settings_sync = swanium_windows_menu_settings_sync(keyboard : LibC::Char**, buttons : LibC::Char**, directions : Int32*) : Nil
  fun smoke_open_settings = swanium_windows_menu_smoke_open_settings : Nil
  fun smoke_settings_tab_count = swanium_windows_menu_smoke_settings_tab_count : Int32
  fun smoke_select_settings_tab = swanium_windows_menu_smoke_select_settings_tab(index : Int32) : Int32
  fun smoke_settings_tabs_named = swanium_windows_menu_smoke_settings_tabs_named : Int32
  fun smoke_status_layout_valid = swanium_windows_menu_smoke_status_layout_valid : Int32
  fun smoke_begin_keyboard_capture = swanium_windows_menu_smoke_begin_keyboard_capture(index : Int32) : Nil
  fun smoke_send_key = swanium_windows_menu_smoke_send_key(virtual_key : Int32) : Nil
  fun smoke_pending_action = swanium_windows_menu_smoke_pending_action : Int32
  fun smoke_keyboard_capture = swanium_windows_menu_smoke_keyboard_capture : Int32
  fun smoke_last_taken_action = swanium_windows_menu_smoke_last_taken_action : Int32
  fun smoke_focus_volume = swanium_windows_menu_smoke_focus_volume : Nil
  fun smoke_game_has_focus = swanium_windows_menu_smoke_game_has_focus : Int32
  fun smoke_post_game_key = swanium_windows_menu_smoke_post_game_key(virtual_key : Int32) : Nil
  fun smoke_close_settings = swanium_windows_menu_smoke_close_settings : Nil
  fun destroy = swanium_windows_menu_destroy : Nil
end

module Swanium::Frontend::WindowsMenu
  OPEN_ROM = 1; PAUSE = 4; RESET = 5; SCALE_1 = 11; SCALE_2 = 12; SCALE_3 = 13; SCALE_4 = 14
  FULLSCREEN = 20; RENDER_NEAREST = 31; RENDER_LINEAR = 32; ABOUT = 41; SETTINGS = 42; QUIT = 43
  SAVE_STATE_BASE = 100; LOAD_STATE_BASE = 200; RECENT_BASE = 300; CLEAR_RECENT = 310

  def self.attach(title : String, volume : Int32, scale : Int32) : Bool
    LibWindowsMenu.attach(title, volume, scale) != 0
  end
  def self.pump : Nil; LibWindowsMenu.pump; end
  def self.take_action : Int32; LibWindowsMenu.take_action; end
  def self.open_rom : String?
    value = LibWindowsMenu.open_rom; value.null? ? nil : String.new(value)
  end
  def self.recent=(paths : Array(String)) : Nil
    pointers = paths.map(&.to_unsafe); pointers << Pointer(LibC::Char).null
    LibWindowsMenu.recent(pointers.to_unsafe)
  end
  def self.recent_path(index : Int32) : String?
    value = LibWindowsMenu.recent_path(index); value.null? ? nil : String.new(value)
  end
  def self.state_slots=(value : Tuple(Array(String), Array(Bool))) : Nil
    labels, available = value
    pointers = labels.map(&.to_unsafe); pointers << Pointer(LibC::Char).null
    flags = available.map { |item| item ? 1 : 0 }
    LibWindowsMenu.state_slots(pointers.to_unsafe, flags.to_unsafe)
  end
  def self.status(title : String, fps : String) : Nil; LibWindowsMenu.status(title, fps); end
  def self.attach_status : Nil; LibWindowsMenu.attach_status; end
  def self.status_height : Int32; LibWindowsMenu.status_height; end
  def self.state(paused : Bool, scale : Int32, fullscreen : Bool, renderer : Int32) : Nil
    LibWindowsMenu.state(paused ? 1 : 0, scale, fullscreen ? 1 : 0, renderer)
  end
  def self.volume : Int32; LibWindowsMenu.volume; end
  def self.error(text : String) : Nil; LibWindowsMenu.error(text); end
  def self.about : Nil; LibWindowsMenu.about; end
  def self.settings : Nil; LibWindowsMenu.settings; end
  def self.settings_sync(keyboard : Array(String), buttons : Array(String), directions : Array(Int32)) : Nil
    keys = keyboard.map(&.to_unsafe); keys << Pointer(LibC::Char).null
    pads = buttons.map(&.to_unsafe); pads << Pointer(LibC::Char).null
    LibWindowsMenu.settings_sync(keys.to_unsafe, pads.to_unsafe, directions.to_unsafe)
  end
  def self.smoke_open_settings : Nil; LibWindowsMenu.smoke_open_settings; end
  def self.smoke_settings_tab_count : Int32; LibWindowsMenu.smoke_settings_tab_count; end
  def self.smoke_select_settings_tab(index : Int32) : Bool; LibWindowsMenu.smoke_select_settings_tab(index) != 0; end
  def self.smoke_settings_tabs_named : Bool; LibWindowsMenu.smoke_settings_tabs_named != 0; end
  def self.smoke_status_layout_valid : Bool; LibWindowsMenu.smoke_status_layout_valid != 0; end
  def self.smoke_begin_keyboard_capture(index : Int32) : Nil; LibWindowsMenu.smoke_begin_keyboard_capture(index); end
  def self.smoke_send_key(virtual_key : Int32) : Nil; LibWindowsMenu.smoke_send_key(virtual_key); end
  def self.smoke_pending_action : Int32; LibWindowsMenu.smoke_pending_action; end
  def self.smoke_keyboard_capture : Int32; LibWindowsMenu.smoke_keyboard_capture; end
  def self.smoke_last_taken_action : Int32; LibWindowsMenu.smoke_last_taken_action; end
  def self.smoke_focus_volume : Nil; LibWindowsMenu.smoke_focus_volume; end
  def self.smoke_game_has_focus : Bool; LibWindowsMenu.smoke_game_has_focus != 0; end
  def self.smoke_post_game_key(virtual_key : Int32) : Nil; LibWindowsMenu.smoke_post_game_key(virtual_key); end
  def self.smoke_close_settings : Nil; LibWindowsMenu.smoke_close_settings; end
  def self.destroy : Nil; LibWindowsMenu.destroy; end
end
