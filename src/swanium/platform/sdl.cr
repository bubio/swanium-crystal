module Swanium
  module Platform
    class SdlError < Exception
    end

    # SDL stays behind this small, checked interface. The emulator core never
    # depends on the C API directly.
    module Sdl
      WINDOWPOS_CENTERED       = 0x2FFF0000_i32
      INIT_VIDEO               = 0x00000020_u32
      INIT_GAMECONTROLLER      = 0x00002000_u32
      WINDOW_SHOWN             = 0x00000004_u32
      RENDERER_ACCELERATED     = 0x00000002_u32
      RENDERER_PRESENTVSYNC    = 0x00000004_u32
      TEXTUREACCESS_STREAMING  =              1
      PIXELFORMAT_RGBA32       =  376840196_u32 # ABGR8888 on little-endian hosts
      EVENT_QUIT               =      0x100_u32
      EVENT_CONTROLLER_ADDED   =      0x650_u32
      EVENT_CONTROLLER_REMOVED =      0x651_u32

      # SDL scancodes are layout-independent and therefore stable for games.
      SC_A      =  4
      SC_D      =  7
      SC_S      = 22
      SC_W      = 26
      SC_X      = 27
      SC_Z      = 29
      SC_RETURN = 40
      SC_ESCAPE = 41
      SC_RIGHT  = 79
      SC_LEFT   = 80
      SC_DOWN   = 81
      SC_UP     = 82

      @[Link("SDL2")]
      lib LibSDL
        struct Event
          type : UInt32
          padding : StaticArray(UInt8, 52)
        end

        fun init = SDL_Init(flags : UInt32) : Int32
        fun quit = SDL_Quit : Nil
        fun get_error = SDL_GetError : LibC::Char*
        fun create_window = SDL_CreateWindow(title : LibC::Char*, x : Int32, y : Int32, width : Int32, height : Int32, flags : UInt32) : Void*
        fun destroy_window = SDL_DestroyWindow(window : Void*) : Nil
        fun create_renderer = SDL_CreateRenderer(window : Void*, index : Int32, flags : UInt32) : Void*
        fun destroy_renderer = SDL_DestroyRenderer(renderer : Void*) : Nil
        fun render_set_logical_size = SDL_RenderSetLogicalSize(renderer : Void*, width : Int32, height : Int32) : Int32
        fun create_texture = SDL_CreateTexture(renderer : Void*, format : UInt32, access : Int32, width : Int32, height : Int32) : Void*
        fun destroy_texture = SDL_DestroyTexture(texture : Void*) : Nil
        fun update_texture = SDL_UpdateTexture(texture : Void*, rect : Void*, pixels : Void*, pitch : Int32) : Int32
        fun render_clear = SDL_RenderClear(renderer : Void*) : Int32
        fun render_copy = SDL_RenderCopy(renderer : Void*, texture : Void*, source : Void*, destination : Void*) : Int32
        fun render_present = SDL_RenderPresent(renderer : Void*) : Nil
        fun poll_event = SDL_PollEvent(event : Event*) : Int32
        fun get_keyboard_state = SDL_GetKeyboardState(count : Int32*) : UInt8*
        fun num_joysticks = SDL_NumJoysticks : Int32
        fun is_game_controller = SDL_IsGameController(index : Int32) : Int32
        fun game_controller_open = SDL_GameControllerOpen(index : Int32) : Void*
        fun game_controller_close = SDL_GameControllerClose(controller : Void*) : Nil
        fun game_controller_get_attached = SDL_GameControllerGetAttached(controller : Void*) : Int32
        fun game_controller_get_button = SDL_GameControllerGetButton(controller : Void*, button : Int32) : UInt8
        fun get_performance_counter = SDL_GetPerformanceCounter : UInt64
        fun get_performance_frequency = SDL_GetPerformanceFrequency : UInt64
        fun delay = SDL_Delay(milliseconds : UInt32) : Nil
      end

      # Interactive, copyright-free display/input verification program. It
      # stays open until Escape or the window close button is pressed.
      def self.video_demo : Nil
        if LibSDL.init(INIT_VIDEO | INIT_GAMECONTROLLER) != 0
          raise SdlError.new(error_message)
        end

        window = Pointer(Void).null
        renderer = Pointer(Void).null
        texture = Pointer(Void).null
        controller = Pointer(Void).null
        begin
          window = LibSDL.create_window(
            "Swanium Crystal - video and input test",
            WINDOWPOS_CENTERED, WINDOWPOS_CENTERED,
            Core::Ppu::SCREEN_WIDTH * 3, Core::Ppu::SCREEN_HEIGHT * 3,
            WINDOW_SHOWN
          )
          raise SdlError.new(error_message) if window.null?
          renderer = LibSDL.create_renderer(window, -1, RENDERER_ACCELERATED | RENDERER_PRESENTVSYNC)
          renderer = LibSDL.create_renderer(window, -1, 0_u32) if renderer.null?
          raise SdlError.new(error_message) if renderer.null?
          check(LibSDL.render_set_logical_size(renderer, Core::Ppu::SCREEN_WIDTH, Core::Ppu::SCREEN_HEIGHT))
          texture = LibSDL.create_texture(renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STREAMING,
            Core::Ppu::SCREEN_WIDTH, Core::Ppu::SCREEN_HEIGHT)
          raise SdlError.new(error_message) if texture.null?
          controller = first_controller

          bus = Core::WonderSwanBus.new(model: Core::WonderSwanModel::Crystal)
          ppu = Core::Ppu.new
          Core::VideoTestPattern.configure(bus)
          event = uninitialized LibSDL::Event
          running = true
          frequency = LibSDL.get_performance_frequency
          frame_ticks = frequency // 60_u64
          next_frame = LibSDL.get_performance_counter
          while running
            while LibSDL.poll_event(pointerof(event)) != 0
              running = false if event.type == EVENT_QUIT
              controller = first_controller if event.type == EVENT_CONTROLLER_ADDED && controller.null?
              if event.type == EVENT_CONTROLLER_REMOVED && !controller.null? && LibSDL.game_controller_get_attached(controller) == 0
                LibSDL.game_controller_close(controller)
                controller = Pointer(Void).null
              end
            end
            keys, escape = input_state(controller)
            running = false if escape
            rgba = Core::VideoTestPattern.render(ppu, bus, keys)
            check(LibSDL.update_texture(texture, Pointer(Void).null, rgba.to_unsafe.as(Void*), Core::Ppu::SCREEN_WIDTH * 4))
            check(LibSDL.render_clear(renderer))
            check(LibSDL.render_copy(renderer, texture, Pointer(Void).null, Pointer(Void).null))
            LibSDL.render_present(renderer)
            # Cap presentation to 60 Hz even on 120 Hz ProMotion displays and
            # when SDL falls back to a renderer without vertical sync.
            next_frame &+= frame_ticks
            now = LibSDL.get_performance_counter
            if next_frame > now
              milliseconds = ((next_frame - now) * 1000_u64 // frequency).to_u32
              LibSDL.delay(milliseconds) if milliseconds > 0
            else
              next_frame = now
            end
          end
        ensure
          LibSDL.game_controller_close(controller) unless controller.null?
          LibSDL.destroy_texture(texture) unless texture.null?
          LibSDL.destroy_renderer(renderer) unless renderer.null?
          LibSDL.destroy_window(window) unless window.null?
          LibSDL.quit
        end
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

      private def self.check(result : Int32) : Nil
        raise SdlError.new(error_message) if result != 0
      end

      private def self.first_controller : Void*
        index = 0
        while index < LibSDL.num_joysticks
          if LibSDL.is_game_controller(index) != 0
            controller = LibSDL.game_controller_open(index)
            return controller unless controller.null?
          end
          index += 1
        end
        Pointer(Void).null
      end

      private def self.input_state(controller : Void*) : Tuple(UInt16, Bool)
        state = LibSDL.get_keyboard_state(Pointer(Int32).null)
        keys = 0_u16
        keys |= Core::WonderSwanKey::X1 if state[SC_RIGHT] != 0
        keys |= Core::WonderSwanKey::X2 if state[SC_DOWN] != 0
        keys |= Core::WonderSwanKey::X3 if state[SC_LEFT] != 0
        keys |= Core::WonderSwanKey::X4 if state[SC_UP] != 0
        keys |= Core::WonderSwanKey::Y1 if state[SC_D] != 0
        keys |= Core::WonderSwanKey::Y2 if state[SC_S] != 0
        keys |= Core::WonderSwanKey::Y3 if state[SC_A] != 0
        keys |= Core::WonderSwanKey::Y4 if state[SC_W] != 0
        keys |= Core::WonderSwanKey::A if state[SC_Z] != 0
        keys |= Core::WonderSwanKey::B if state[SC_X] != 0
        keys |= Core::WonderSwanKey::Start if state[SC_RETURN] != 0
        unless controller.null?
          keys |= Core::WonderSwanKey::A if LibSDL.game_controller_get_button(controller, 0) != 0
          keys |= Core::WonderSwanKey::B if LibSDL.game_controller_get_button(controller, 1) != 0
          keys |= Core::WonderSwanKey::Start if LibSDL.game_controller_get_button(controller, 6) != 0
          keys |= Core::WonderSwanKey::X4 if LibSDL.game_controller_get_button(controller, 11) != 0
          keys |= Core::WonderSwanKey::X2 if LibSDL.game_controller_get_button(controller, 12) != 0
          keys |= Core::WonderSwanKey::X3 if LibSDL.game_controller_get_button(controller, 13) != 0
          keys |= Core::WonderSwanKey::X1 if LibSDL.game_controller_get_button(controller, 14) != 0
        end
        {keys, state[SC_ESCAPE] != 0}
      end
    end
  end
end
