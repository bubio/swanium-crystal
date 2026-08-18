@[Link("gtk-3")]
lib LibLinuxMenu
  fun build = swanium_linux_menu_build(title : LibC::Char*, volume : Int32, scale : Int32) : Nil
  fun pump = swanium_linux_menu_pump : Nil
  fun take_action = swanium_linux_menu_take_action : Int32
  fun open_rom = swanium_linux_menu_open_rom : LibC::Char*
  fun status = swanium_linux_menu_status(text : LibC::Char*) : Nil
  fun recent = swanium_linux_menu_recent(paths : LibC::Char**) : Nil
  fun recent_path = swanium_linux_menu_recent_path(index : Int32) : LibC::Char*
  fun state_slots = swanium_linux_menu_state_slots(labels : LibC::Char**, available : Int32*) : Nil
  fun present = swanium_linux_menu_present(pixels : UInt8*, width : Int32, height : Int32) : Nil
  fun scale = swanium_linux_menu_scale(scale : Int32) : Nil
  fun fullscreen = swanium_linux_menu_fullscreen(enabled : Int32) : Nil
  fun volume = swanium_linux_menu_volume : Int32
  fun error = swanium_linux_menu_error(text : LibC::Char*) : Nil
  fun about = swanium_linux_menu_about : Nil
  fun settings = swanium_linux_menu_settings : Nil
  fun settings_sync = swanium_linux_menu_settings_sync(keyboard : LibC::Char**, buttons : LibC::Char**, directions : Int32*) : Nil
  fun destroy = swanium_linux_menu_destroy : Nil
end

module Swanium::Frontend::LinuxMenu
  OPEN_ROM = 1; PAUSE = 4; RESET = 5; SCALE_1 = 11; SCALE_2 = 12; SCALE_3 = 13; SCALE_4    = 14
  FULLSCREEN = 20; RENDER_NEAREST = 31; RENDER_LINEAR = 32; ABOUT = 41; SETTINGS = 42; QUIT            =  43
  SAVE_STATE_BASE = 100; LOAD_STATE_BASE = 200; RECENT_BASE = 300; CLEAR_RECENT = 310

  def self.build(title : String, volume : Int32, scale : Int32) : Nil
    LibLinuxMenu.build(title, volume, scale)
  end

  def self.pump : Nil
    LibLinuxMenu.pump
  end

  def self.take_action : Int32
    LibLinuxMenu.take_action
  end

  def self.open_rom : String?
    path = LibLinuxMenu.open_rom; path.null? ? nil : String.new(path)
  end

  def self.status=(value : String) : Nil
    LibLinuxMenu.status(value)
  end

  def self.recent=(paths : Array(String)) : Nil
    pointers = paths.map(&.to_unsafe); pointers << Pointer(LibC::Char).null
    LibLinuxMenu.recent(pointers.to_unsafe)
  end

  def self.recent_path(index : Int32) : String?
    value = LibLinuxMenu.recent_path(index); value.null? ? nil : String.new(value)
  end

  def self.state_slots=(value : Tuple(Array(String), Array(Bool))) : Nil
    labels, available = value
    pointers = labels.map(&.to_unsafe); pointers << Pointer(LibC::Char).null
    flags = available.map { |item| item ? 1 : 0 }
    LibLinuxMenu.state_slots(pointers.to_unsafe, flags.to_unsafe)
  end

  def self.volume : Int32
    LibLinuxMenu.volume
  end

  def self.error(value : String) : Nil
    LibLinuxMenu.error(value)
  end

  def self.about : Nil
    LibLinuxMenu.about
  end

  def self.settings : Nil
    LibLinuxMenu.settings
  end

  def self.settings_sync(keyboard : Array(String), buttons : Array(String), directions : Array(Int32)) : Nil
    key_pointers = keyboard.map(&.to_unsafe); key_pointers << Pointer(LibC::Char).null
    button_pointers = buttons.map(&.to_unsafe); button_pointers << Pointer(LibC::Char).null
    LibLinuxMenu.settings_sync(key_pointers.to_unsafe, button_pointers.to_unsafe, directions.to_unsafe)
  end

  def self.present(pixels : Bytes, width : Int32, height : Int32) : Nil
    LibLinuxMenu.present(pixels.to_unsafe, width, height)
  end

  def self.scale=(value : Int32) : Nil
    LibLinuxMenu.scale(value)
  end

  def self.fullscreen=(value : Bool) : Nil
    LibLinuxMenu.fullscreen(value ? 1 : 0)
  end

  def self.destroy : Nil
    LibLinuxMenu.destroy
  end
end
