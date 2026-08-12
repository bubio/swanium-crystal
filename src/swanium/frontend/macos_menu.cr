@[Link(framework: "Cocoa")]
lib LibMacOSMenu
  fun build = swanium_macos_menu_build : Nil
  fun take_action = swanium_macos_menu_take_action : Int32
  fun hide_menu = swanium_macos_menu_hide : Nil
  fun attach_status = swanium_macos_status_attach(window : Void*) : Nil
  fun update_status = swanium_macos_status_update(text : LibC::Char*) : Nil
  fun status_volume = swanium_macos_status_volume : Int32
end

module Swanium
  module Frontend
    # AppKit submenus used where libui-ng exposes only flat menu items.
    module MacosMenu
      OPEN_ROM        =   1
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

      def self.install : Nil
        LibMacOSMenu.build
      end

      def self.take_action : Int32
        LibMacOSMenu.take_action
      end

      def self.hide_libui_menu : Nil
        LibMacOSMenu.hide_menu
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
    end
  end
end
