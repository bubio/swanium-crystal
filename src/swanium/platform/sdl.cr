module Swanium
  module Platform
    class SdlError < Exception
    end

    # SDL stays behind this small, checked interface. The emulator core never
    # depends on the C API directly.
    module Sdl
      WINDOWPOS_CENTERED = 0x2FFF0000_i32
      INIT_VIDEO         = 0x00000020_u32
      WINDOW_SHOWN       = 0x00000004_u32

      @[Link("SDL2")]
      lib LibSDL
        fun init = SDL_Init(flags : UInt32) : Int32
        fun quit = SDL_Quit : Nil
        fun get_error = SDL_GetError : LibC::Char*
        fun create_window = SDL_CreateWindow(title : LibC::Char*, x : Int32, y : Int32, width : Int32, height : Int32, flags : UInt32) : Void*
        fun destroy_window = SDL_DestroyWindow(window : Void*) : Nil
        fun delay = SDL_Delay(milliseconds : UInt32) : Nil
      end

      def self.smoke_test : Nil
        if LibSDL.init(INIT_VIDEO) != 0
          raise SdlError.new(error_message)
        end

        begin
          window = LibSDL.create_window(
            "Swanium Crystal SDL2 smoke test",
            WINDOWPOS_CENTERED,
            WINDOWPOS_CENTERED,
            320,
            240,
            WINDOW_SHOWN
          )
          raise SdlError.new(error_message) if window.null?

          begin
            LibSDL.delay(250_u32)
          ensure
            LibSDL.destroy_window(window)
          end
        ensure
          LibSDL.quit
        end
      end

      private def self.error_message : String
        error = LibSDL.get_error
        error.null? ? "SDL2 initialization failed" : String.new(error)
      end
    end
  end
end
