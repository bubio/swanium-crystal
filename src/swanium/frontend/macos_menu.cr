@[Link(framework: "Cocoa")]
lib LibMacOSMenu
  fun build = swanium_macos_menu_build : Nil
  fun take_action = swanium_macos_menu_take_action : Int32
  fun hide_menu = swanium_macos_menu_hide : Nil
  fun open_rom = swanium_macos_menu_open_rom : LibC::Char*
  fun show_about = swanium_macos_menu_show_about : Nil
  fun attach_status = swanium_macos_status_attach_sdl_window(window : Void*) : Nil
  fun update_status = swanium_macos_status_update(text : LibC::Char*) : Nil
  fun status_volume = swanium_macos_status_volume : Int32
  fun set_status_volume = swanium_macos_status_set_volume(value : Int32) : Nil
  fun status_reserved_height = swanium_macos_status_reserved_height_pixels(window : Void*) : Int32
  fun set_recent_roms = swanium_macos_menu_set_recent_roms(paths : LibC::Char**) : Nil
  fun recent_rom = swanium_macos_menu_recent_rom(index : Int32) : LibC::Char*
  fun update_menu_state = swanium_macos_menu_update_state(paused : Bool, scale : Int32, fullscreen : Bool, renderer : Int32) : Nil
  fun set_load_slots = swanium_macos_menu_set_load_slots(slots : Int32*) : Nil
end

module Swanium
  module Frontend
    # AppKit submenus used where libui-ng exposes only flat menu items.
    module MacosMenu
      OPEN_ROM        =   1
      ABOUT           =  41
      SETTINGS        =  42
      QUIT            =  43
      SAVE_STATE_BASE = 100
      LOAD_STATE_BASE = 200
      PAUSE           =   4
      RESET           =   5
      SCALE_1         =  11
      SCALE_2         =  12
      SCALE_3         =  13
      SCALE_4         =  14
      FULLSCREEN      =  20
      RENDER_NEAREST  =  31
      RENDER_LINEAR   =  32
      RECENT_BASE     = 300
      CLEAR_RECENT    = 310

      def self.install : Nil
        LibMacOSMenu.build
      end

      def self.take_action : Int32
        LibMacOSMenu.take_action
      end

      def self.set_recent_roms(paths : Array(String)) : Nil
        pointers = paths.map(&.to_unsafe)
        pointers << Pointer(LibC::Char).null
        LibMacOSMenu.set_recent_roms(pointers.to_unsafe)
      end

      def self.recent_rom(index : Int32) : String?
        path = LibMacOSMenu.recent_rom(index)
        path.null? ? nil : String.new(path)
      end

      def self.update_menu_state(paused : Bool, scale : Int32, fullscreen : Bool, renderer : Int32) : Nil
        LibMacOSMenu.update_menu_state(paused, scale, fullscreen, renderer)
      end

      def self.set_load_slots(slots : Array(Bool)) : Nil
        values = slots.map { |available| available ? 1 : 0 }
        LibMacOSMenu.set_load_slots(values.to_unsafe)
      end

      def self.open_rom : String?
        path = LibMacOSMenu.open_rom
        path.null? ? nil : String.new(path)
      end

      def self.show_about : Nil
        LibMacOSMenu.show_about
      end

      def self.attach_status(window : Void*) : Nil
        LibMacOSMenu.attach_status(window)
      end

      def self.update_status(text : String) : Nil
        LibMacOSMenu.update_status(text)
      end

      def self.volume : Int32
        LibMacOSMenu.status_volume
      end

      def self.volume=(value : Int32) : Nil
        LibMacOSMenu.set_status_volume(value)
      end

      def self.reserved_status_height(window : Void*) : Int32
        LibMacOSMenu.status_reserved_height(window)
      end
    end
  end
end
