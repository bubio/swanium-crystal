require "./audio_resampler"
require "../frontend/video_test_pattern"
require "../frontend/native_controls"

module Swanium
  module Platform
    class SdlError < Exception
    end

    # SDL stays behind this small, checked interface. The emulator core never
    # depends on the C API directly.
    module Sdl
      WINDOWPOS_CENTERED         = 0x2FFF0000_i32
      INIT_VIDEO                 = 0x00000020_u32
      INIT_AUDIO                 = 0x00000010_u32
      INIT_GAMECONTROLLER        = 0x00002000_u32
      WINDOW_SHOWN               = 0x00000004_u32
      WINDOW_FULLSCREEN_DESKTOP  = 0x00001001_u32
      RENDERER_ACCELERATED       = 0x00000002_u32
      RENDERER_PRESENTVSYNC      = 0x00000004_u32
      TEXTUREACCESS_STREAMING    =              1
      PIXELFORMAT_RGBA32         =  376840196_u32 # ABGR8888 on little-endian hosts
      AUDIO_FRAMES_PER_BUFFER    =        256_u16
      AUDIO_PREROLL_FRAMES       =              3
      AUDIO_MAX_QUEUE_BYTES      =      9_600_u32 # 100 ms at 24 kHz stereo S16
      AUDIO_ALLOW_RATE_CHANGE    =           0x01
      AUDIO_ALLOW_SAMPLES_CHANGE =           0x08
      EVENT_QUIT                 =      0x100_u32
      EVENT_KEYDOWN              =      0x300_u32
      EVENT_CONTROLLER_ADDED     =      0x650_u32
      EVENT_CONTROLLER_REMOVED   =      0x651_u32

      # SDL scancodes are layout-independent and therefore stable for games.
      SC_A        =  4
      SC_D        =  7
      SC_S        = 22
      SC_W        = 26
      SC_X        = 27
      SC_Z        = 29
      SC_RETURN   = 40
      SC_ESCAPE   = 41
      SC_SPACE    = 44
      SC_F1       = 58
      SC_F5       = 62
      SC_F9       = 66
      SC_N        = 17
      SC_1        = 30
      SC_2        = 31
      SC_3        = 32
      SC_PAGEUP   = 75
      SC_PAGEDOWN = 78
      SC_RIGHT    = 79
      SC_LEFT     = 80
      SC_DOWN     = 81
      SC_UP       = 82

      @[Link("SDL2")]
      lib LibSDL
        struct Rect
          x : Int32
          y : Int32
          w : Int32
          h : Int32
        end

        struct Event
          type : UInt32
          padding : StaticArray(UInt8, 52)
        end

        struct KeyboardEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          state : UInt8
          repeat : UInt8
          padding : UInt16
          scancode : Int32
          keycode : Int32
          modifiers : UInt16
          unused : UInt32
        end

        struct AudioSpec
          freq : Int32
          format : UInt16
          channels : UInt8
          silence : UInt8
          samples : UInt16
          padding : UInt16
          size : UInt32
          callback : Void*
          userdata : Void*
        end

        fun init = SDL_Init(flags : UInt32) : Int32
        fun quit = SDL_Quit : Nil
        fun get_error = SDL_GetError : LibC::Char*
        fun create_window = SDL_CreateWindow(title : LibC::Char*, x : Int32, y : Int32, width : Int32, height : Int32, flags : UInt32) : Void*
        fun destroy_window = SDL_DestroyWindow(window : Void*) : Nil
        fun set_window_size = SDL_SetWindowSize(window : Void*, width : Int32, height : Int32) : Nil
        fun set_window_fullscreen = SDL_SetWindowFullscreen(window : Void*, flags : UInt32) : Int32
        fun create_renderer = SDL_CreateRenderer(window : Void*, index : Int32, flags : UInt32) : Void*
        fun destroy_renderer = SDL_DestroyRenderer(renderer : Void*) : Nil
        fun create_texture = SDL_CreateTexture(renderer : Void*, format : UInt32, access : Int32, width : Int32, height : Int32) : Void*
        fun destroy_texture = SDL_DestroyTexture(texture : Void*) : Nil
        fun set_texture_scale_mode = SDL_SetTextureScaleMode(texture : Void*, scale_mode : Int32) : Int32
        fun update_texture = SDL_UpdateTexture(texture : Void*, rect : Void*, pixels : Void*, pitch : Int32) : Int32
        fun render_clear = SDL_RenderClear(renderer : Void*) : Int32
        fun render_copy = SDL_RenderCopy(renderer : Void*, texture : Void*, source : Void*, destination : Void*) : Int32
        fun get_renderer_output_size = SDL_GetRendererOutputSize(renderer : Void*, width : Int32*, height : Int32*) : Int32
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
        fun open_audio_device = SDL_OpenAudioDevice(device : LibC::Char*, capture : Int32, desired : AudioSpec*, obtained : AudioSpec*, allowed_changes : Int32) : UInt32
        fun close_audio_device = SDL_CloseAudioDevice(device : UInt32) : Nil
        fun pause_audio_device = SDL_PauseAudioDevice(device : UInt32, pause : Int32) : Nil
        fun queue_audio = SDL_QueueAudio(device : UInt32, data : Void*, length : UInt32) : Int32
        fun get_queued_audio_size = SDL_GetQueuedAudioSize(device : UInt32) : UInt32
        fun clear_queued_audio = SDL_ClearQueuedAudio(device : UInt32) : Nil
      end

      # Interactive, copyright-free display/input verification program. It
      # stays open until the window close button is pressed. Escape leaves
      # fullscreen mode when it is active.
      def self.video_demo : Nil
        controls = Frontend::NativeControls.start("Video demo")
        if LibSDL.init(INIT_VIDEO | INIT_AUDIO | INIT_GAMECONTROLLER) != 0
          controls.close
          raise SdlError.new(error_message)
        end

        window = Pointer(Void).null
        renderer = Pointer(Void).null
        texture = Pointer(Void).null
        controller = Pointer(Void).null
        audio_device = 0_u32
        begin
          window = LibSDL.create_window(
            "Swanium Crystal - video and input test",
            WINDOWPOS_CENTERED, WINDOWPOS_CENTERED,
            Core::Ppu::SCREEN_WIDTH * 3, Core::Ppu::SCREEN_HEIGHT * 3 + 22,
            WINDOW_SHOWN
          )
          raise SdlError.new(error_message) if window.null?
          controls.install_menus
          renderer = LibSDL.create_renderer(window, -1, RENDERER_ACCELERATED | RENDERER_PRESENTVSYNC)
          renderer = LibSDL.create_renderer(window, -1, 0_u32) if renderer.null?
          raise SdlError.new(error_message) if renderer.null?
          texture = LibSDL.create_texture(renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STREAMING,
            Core::Ppu::SCREEN_WIDTH, Core::Ppu::SCREEN_HEIGHT)
          raise SdlError.new(error_message) if texture.null?
          controls.attach_status(window)
          controller = first_controller
          controls.update_state_slots("demo")

          desired = LibSDL::AudioSpec.new
          desired.freq = Core::Apu::OUTPUT_SAMPLE_RATE.to_i32
          desired.format = 0x8010_u16 # AUDIO_S16SYS
          desired.channels = 2_u8
          desired.samples = AUDIO_FRAMES_PER_BUFFER
          desired.callback = Pointer(Void).null
          desired.userdata = Pointer(Void).null
          audio_device = LibSDL.open_audio_device(Pointer(LibC::Char).null, 0, pointerof(desired), Pointer(LibSDL::AudioSpec).null, 0)
          raise SdlError.new(error_message) if audio_device == 0_u32
          LibSDL.pause_audio_device(audio_device, 0)

          bus = Core::WonderSwanBus.new(model: Core::WonderSwanModel::Crystal)
          machine = Core::Machine.new
          debugger = Frontend::Debugger.new
          Frontend::VideoTestPattern.configure(bus)
          configure_audio_test(bus)
          0x10000.times { |address| bus.write_u8(address.to_u32, 0x90_u8) }
          machine.cpu.reset(0_u16, 0_u16)
          event = uninitialized LibSDL::Event
          running = true
          frequency = LibSDL.get_performance_frequency
          frame_ticks = frequency // 60_u64
          next_frame = LibSDL.get_performance_counter
          presented_frames = 0_u32
          audio_underruns = 0_u32
          fps = 60.0
          fps_anchor = LibSDL.get_performance_counter
          fps_frames = 0_u32
          fullscreen = false
          scale = 3
          renderer_mode = 0
          while running && !controls.quit_requested
            while LibSDL.poll_event(pointerof(event)) != 0
              running = false if event.type == EVENT_QUIT
              controller = first_controller if event.type == EVENT_CONTROLLER_ADDED && controller.null?
              if event.type == EVENT_CONTROLLER_REMOVED && !controller.null? && LibSDL.game_controller_get_attached(controller) == 0
                LibSDL.game_controller_close(controller)
                controller = Pointer(Void).null
              end
              if event.type == EVENT_KEYDOWN
                keyboard = pointerof(event).as(LibSDL::KeyboardEvent*).value
                handle_debug_key(keyboard.scancode, keyboard.repeat, debugger, machine, bus, audio_device)
              end
            end
            controls.pump
            if controls.take_pause_request?
              debugger.toggle_pause
              LibSDL.pause_audio_device(audio_device, debugger.paused ? 1 : 0)
            end
            if controls.take_reset_request?
              machine.cpu.reset(0_u16, 0_u16)
              LibSDL.clear_queued_audio(audio_device)
            end
            if requested_scale = controls.take_scale_request
              scale = requested_scale
              LibSDL.set_window_size(window, Core::Ppu::SCREEN_WIDTH * scale, Core::Ppu::SCREEN_HEIGHT * scale + 22)
            end
            if controls.take_fullscreen_request?
              fullscreen = !fullscreen
              check(LibSDL.set_window_fullscreen(window, fullscreen ? WINDOW_FULLSCREEN_DESKTOP : 0_u32))
            end
            if requested_renderer = controls.take_renderer_request
              renderer_mode = requested_renderer
              check(LibSDL.set_texture_scale_mode(texture, renderer_mode))
            end
            if slot = controls.take_save_state_request
              StateStore.default.save(machine, bus, "demo", slot)
              controls.update_state_slots("demo")
            end
            if slot = controls.take_load_state_request
              StateStore.default.load(machine, bus, "demo", slot)
              LibSDL.clear_queued_audio(audio_device)
            end
            keys, escape = input_state(controller)
            if escape && fullscreen
              fullscreen = false
              check(LibSDL.set_window_fullscreen(window, 0_u32))
            end
            if debugger.paused
              debugger.run_instruction?(machine, bus)
            else
              Frontend::VideoTestPattern.apply_input(bus, keys)
              machine.run_wonder_swan_frame(bus, keys)
            end
            rgba = machine.framebuffer_rgba
            queued_audio = LibSDL.get_queued_audio_size(audio_device)
            audio_underruns &+= 1_u32 if presented_frames > 2_u32 && queued_audio < 256_u32 && !debugger.paused
            unless debugger.paused
              queue_audio(audio_device, machine.apu.drain_samples, nil, controls.volume)
            end
            latency_ms = queued_audio * 1000_u32 // (Core::Apu::OUTPUT_SAMPLE_RATE * 4_u32)
            debugger.render(rgba, machine, bus, latency_ms, audio_underruns)
            fps_frames &+= 1_u32
            elapsed = LibSDL.get_performance_counter - fps_anchor
            if elapsed >= frequency // 2_u64
              fps = fps_frames.to_f64 * frequency.to_f64 / elapsed.to_f64
              fps_frames = 0_u32
              fps_anchor = LibSDL.get_performance_counter
            end
            controls.update_status("Video demo", fps, debugger.paused)
            controls.update_menu_state(debugger.paused, scale, fullscreen, renderer_mode)
            check(LibSDL.update_texture(texture, Pointer(Void).null, rgba.to_unsafe.as(Void*), Core::Ppu::SCREEN_WIDTH * 4))
            check(LibSDL.render_clear(renderer))
            render_game(renderer, texture, Core::Ppu::SCREEN_WIDTH, Core::Ppu::SCREEN_HEIGHT, controls.reserved_status_height(window))
            LibSDL.render_present(renderer)
            presented_frames &+= 1_u32
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
          LibSDL.close_audio_device(audio_device) unless audio_device == 0_u32
          LibSDL.game_controller_close(controller) unless controller.null?
          LibSDL.destroy_texture(texture) unless texture.null?
          LibSDL.destroy_renderer(renderer) unless renderer.null?
          LibSDL.destroy_window(window) unless window.null?
          LibSDL.quit
          controls.close
        end
      end

      # Run one explicitly selected local cartridge. File loading and filename
      # handling stay in the application layer; this method receives only
      # validated bytes and a display/save label.
      # Returns a newly selected ROM path when the native File > Open ROM…
      # action asks the application layer to replace the current cartridge.
      def self.play(cartridge : Core::CartridgeImage, title : String) : String?
        controls = Frontend::NativeControls.start(title)
        if LibSDL.init(INIT_VIDEO | INIT_AUDIO | INIT_GAMECONTROLLER) != 0
          controls.close
          raise SdlError.new(error_message)
        end

        window = Pointer(Void).null
        renderer = Pointer(Void).null
        texture = Pointer(Void).null
        controller = Pointer(Void).null
        audio_device = 0_u32
        opened_rom_path = nil.as(String?)
        bus = Core::WonderSwanBus.from_cartridge(cartridge)
        machine = Core::Machine.new
        machine.cpu.reset(0xFFFF_u16, 0_u16)
        debugger = Frontend::Debugger.new
        vertical = cartridge.header.vertical
        display_width = vertical ? Core::Ppu::SCREEN_HEIGHT : Core::Ppu::SCREEN_WIDTH
        display_height = vertical ? Core::Ppu::SCREEN_WIDTH : Core::Ppu::SCREEN_HEIGHT
        rotated_rgba = vertical ? Bytes.new(Core::Ppu::SCREEN_WIDTH * Core::Ppu::SCREEN_HEIGHT * 4, 0_u8) : nil
        begin
          StateStore.default.load_cartridge_save(bus, title)
          window = LibSDL.create_window(
            "Swanium Crystal - #{title}", WINDOWPOS_CENTERED, WINDOWPOS_CENTERED,
            display_width * 3, display_height * 3 + 22, WINDOW_SHOWN
          )
          raise SdlError.new(error_message) if window.null?
          controls.install_menus
          renderer = LibSDL.create_renderer(window, -1, RENDERER_ACCELERATED | RENDERER_PRESENTVSYNC)
          renderer = LibSDL.create_renderer(window, -1, 0_u32) if renderer.null?
          raise SdlError.new(error_message) if renderer.null?
          texture = LibSDL.create_texture(renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STREAMING,
            display_width, display_height)
          raise SdlError.new(error_message) if texture.null?
          controls.attach_status(window)
          controller = first_controller
          controls.update_state_slots(title)

          desired = LibSDL::AudioSpec.new
          desired.freq = Core::Apu::OUTPUT_SAMPLE_RATE.to_i32
          desired.format = 0x8010_u16
          desired.channels = 2_u8
          desired.samples = AUDIO_FRAMES_PER_BUFFER
          desired.callback = Pointer(Void).null
          desired.userdata = Pointer(Void).null
          obtained = LibSDL::AudioSpec.new
          audio_device = LibSDL.open_audio_device(Pointer(LibC::Char).null, 0, pointerof(desired), pointerof(obtained),
            AUDIO_ALLOW_RATE_CHANGE | AUDIO_ALLOW_SAMPLES_CHANGE)
          raise SdlError.new(error_message) if audio_device == 0_u32
          raise SdlError.new("SDL2 selected an unsupported audio format") unless obtained.format == desired.format && obtained.channels == 2_u8
          resampler = AudioResampler.new(Core::Apu::OUTPUT_SAMPLE_RATE.to_i32, obtained.freq)
          AUDIO_PREROLL_FRAMES.times do
            machine.run_wonder_swan_frame(bus)
            queue_audio(audio_device, machine.apu.drain_samples, resampler)
          end
          LibSDL.pause_audio_device(audio_device, 0)

          event = uninitialized LibSDL::Event
          running = true
          frequency = LibSDL.get_performance_frequency
          frame_ticks = frequency // 60_u64
          next_frame = LibSDL.get_performance_counter
          presented_frames = 0_u32
          audio_underruns = 0_u32
          fps = 60.0
          fps_anchor = LibSDL.get_performance_counter
          fps_frames = 0_u32
          fullscreen = false
          scale = 3
          renderer_mode = 0
          while running && !controls.quit_requested
            while LibSDL.poll_event(pointerof(event)) != 0
              running = false if event.type == EVENT_QUIT
              controller = first_controller if event.type == EVENT_CONTROLLER_ADDED && controller.null?
              if event.type == EVENT_CONTROLLER_REMOVED && !controller.null? && LibSDL.game_controller_get_attached(controller) == 0
                LibSDL.game_controller_close(controller)
                controller = Pointer(Void).null
              end
              if event.type == EVENT_KEYDOWN
                keyboard = pointerof(event).as(LibSDL::KeyboardEvent*).value
                handle_debug_key(keyboard.scancode, keyboard.repeat, debugger, machine, bus, audio_device, title)
              end
            end
            controls.pump
            if path = controls.take_open_rom_path
              opened_rom_path = path
              running = false
              next
            end
            if controls.take_pause_request?
              debugger.toggle_pause
              LibSDL.pause_audio_device(audio_device, debugger.paused ? 1 : 0)
            end
            if controls.take_reset_request?
              machine.cpu.reset(0xFFFF_u16, 0_u16)
              LibSDL.clear_queued_audio(audio_device)
            end
            if requested_scale = controls.take_scale_request
              scale = requested_scale
              LibSDL.set_window_size(window, display_width * scale, display_height * scale + 22)
            end
            if controls.take_fullscreen_request?
              fullscreen = !fullscreen
              check(LibSDL.set_window_fullscreen(window, fullscreen ? WINDOW_FULLSCREEN_DESKTOP : 0_u32))
            end
            if requested_renderer = controls.take_renderer_request
              renderer_mode = requested_renderer
              check(LibSDL.set_texture_scale_mode(texture, renderer_mode))
            end
            if slot = controls.take_save_state_request
              StateStore.default.save(machine, bus, title, slot)
              controls.update_state_slots(title)
            end
            if slot = controls.take_load_state_request
              StateStore.default.load(machine, bus, title, slot)
              LibSDL.clear_queued_audio(audio_device)
            end
            keys, escape = input_state(controller)
            # The display rotates left, so host directions need the opposite
            # (right) compensation to keep on-screen movement intuitive.
            keys = rotate_input_right(keys) if vertical
            if escape && fullscreen
              fullscreen = false
              check(LibSDL.set_window_fullscreen(window, 0_u32))
            end
            queued_audio = LibSDL.get_queued_audio_size(audio_device)
            if debugger.paused
              debugger.run_instruction?(machine, bus)
            else
              # Match the original frontend's audio-led worker: catch up when
              # the host callback has drained below 50 ms, but never run an
              # unbounded burst on the UI thread.
              frames_run = 0
              while queued_audio < audio_target_bytes(obtained.freq) && frames_run < 4
                machine.run_wonder_swan_frame(bus, keys)
                queue_audio(audio_device, machine.apu.drain_samples, resampler, controls.volume)
                queued_audio = LibSDL.get_queued_audio_size(audio_device)
                frames_run += 1
              end
            end
            audio_underruns &+= 1_u32 if presented_frames > 2_u32 && queued_audio < 1_024_u32 && !debugger.paused
            latency_ms = queued_audio * 1000_u32 // (obtained.freq.to_u32 * 4_u32)
            rgba = machine.framebuffer_rgba
            debugger.render(rgba, machine, bus, latency_ms, audio_underruns)
            displayed_rgba = if destination = rotated_rgba
                               rotate_left(rgba, destination)
                               destination
                             else
                               rgba
                             end
            fps_frames &+= 1_u32
            elapsed = LibSDL.get_performance_counter - fps_anchor
            if elapsed >= frequency // 2_u64
              fps = fps_frames.to_f64 * frequency.to_f64 / elapsed.to_f64
              fps_frames = 0_u32
              fps_anchor = LibSDL.get_performance_counter
            end
            controls.update_status(title, fps, debugger.paused)
            controls.update_menu_state(debugger.paused, scale, fullscreen, renderer_mode)
            check(LibSDL.update_texture(texture, Pointer(Void).null, displayed_rgba.to_unsafe.as(Void*), display_width * 4))
            check(LibSDL.render_clear(renderer))
            render_game(renderer, texture, display_width, display_height, controls.reserved_status_height(window))
            LibSDL.render_present(renderer)
            presented_frames &+= 1_u32
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
          StateStore.default.save_cartridge_save(bus, title)
          LibSDL.close_audio_device(audio_device) unless audio_device == 0_u32
          LibSDL.game_controller_close(controller) unless controller.null?
          LibSDL.destroy_texture(texture) unless texture.null?
          LibSDL.destroy_renderer(renderer) unless renderer.null?
          LibSDL.destroy_window(window) unless window.null?
          LibSDL.quit
          controls.close
        end
        opened_rom_path
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

      private def self.render_game(renderer : Void*, texture : Void*, game_width : Int32, game_height : Int32, reserved_status_height : Int32) : Nil
        output_width = 0
        output_height = 0
        check(LibSDL.get_renderer_output_size(renderer, pointerof(output_width), pointerof(output_height)))
        available_height = {output_height - reserved_status_height, 1}.max
        scale = {output_width.to_f64 / game_width, available_height.to_f64 / game_height}.min
        width = (game_width * scale).round.to_i
        height = (game_height * scale).round.to_i
        destination = LibSDL::Rect.new(
          x: (output_width - width) // 2,
          y: (available_height - height) // 2,
          w: width,
          h: height
        )
        check(LibSDL.render_copy(renderer, texture, Pointer(Void).null, pointerof(destination).as(Void*)))
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
        # Match Swanium's established horizontal default bindings exactly.
        bindings = Frontend::InputBindings.default
        keys |= Core::WonderSwanKey::X1 if state[bindings.scancode(:x1)] != 0
        keys |= Core::WonderSwanKey::X2 if state[bindings.scancode(:x2)] != 0
        keys |= Core::WonderSwanKey::X3 if state[bindings.scancode(:x3)] != 0
        keys |= Core::WonderSwanKey::X4 if state[bindings.scancode(:x4)] != 0
        keys |= Core::WonderSwanKey::Y1 if state[bindings.scancode(:y1)] != 0
        keys |= Core::WonderSwanKey::Y2 if state[bindings.scancode(:y2)] != 0
        keys |= Core::WonderSwanKey::Y3 if state[bindings.scancode(:y3)] != 0
        keys |= Core::WonderSwanKey::Y4 if state[bindings.scancode(:y4)] != 0
        keys |= Core::WonderSwanKey::A if state[bindings.scancode(:a)] != 0
        keys |= Core::WonderSwanKey::B if state[bindings.scancode(:b)] != 0
        keys |= Core::WonderSwanKey::Start if state[bindings.scancode(:start)] != 0
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

      private def self.rotate_input_right(keys : UInt16) : UInt16
        rotated = keys & ~(0x00FF_u16)
        rotated |= Core::WonderSwanKey::X2 if (keys & Core::WonderSwanKey::X1) != 0_u16
        rotated |= Core::WonderSwanKey::X3 if (keys & Core::WonderSwanKey::X2) != 0_u16
        rotated |= Core::WonderSwanKey::X4 if (keys & Core::WonderSwanKey::X3) != 0_u16
        rotated |= Core::WonderSwanKey::X1 if (keys & Core::WonderSwanKey::X4) != 0_u16
        rotated |= Core::WonderSwanKey::Y2 if (keys & Core::WonderSwanKey::Y1) != 0_u16
        rotated |= Core::WonderSwanKey::Y3 if (keys & Core::WonderSwanKey::Y2) != 0_u16
        rotated |= Core::WonderSwanKey::Y4 if (keys & Core::WonderSwanKey::Y3) != 0_u16
        rotated |= Core::WonderSwanKey::Y1 if (keys & Core::WonderSwanKey::Y4) != 0_u16
        rotated
      end

      # Source is 224x144 landscape RGBA. The cartridge footer's vertical flag
      # requests the same left rotation used by the original Swanium frontend.
      private def self.rotate_left(source : Bytes, destination : Bytes) : Nil
        source_y = 0
        while source_y < Core::Ppu::SCREEN_HEIGHT
          source_x = 0
          while source_x < Core::Ppu::SCREEN_WIDTH
            source_offset = (source_y * Core::Ppu::SCREEN_WIDTH + source_x) * 4
            destination_offset = ((Core::Ppu::SCREEN_WIDTH - 1 - source_x) * Core::Ppu::SCREEN_HEIGHT + source_y) * 4
            destination[destination_offset] = source[source_offset]
            destination[destination_offset + 1] = source[source_offset + 1]
            destination[destination_offset + 2] = source[source_offset + 2]
            destination[destination_offset + 3] = source[source_offset + 3]
            source_x += 1
          end
          source_y += 1
        end
      end

      private def self.configure_audio_test(bus : Core::WonderSwanBus) : Nil
        bus.write_io(0x8F_u8, 8_u8)
        16.times { |index| bus.write_u8((0x200 + index).to_u32, index < 8 ? 0x00_u8 : 0xFF_u8) }
        pitch = 1830_u16
        bus.write_io(0x80_u8, (pitch & 0xFF_u16).to_u8)
        bus.write_io(0x81_u8, (pitch >> 8).to_u8)
        bus.write_io(0x88_u8, 0x22_u8)
        bus.write_io(0x90_u8, 0x01_u8)
        bus.write_io(0x91_u8, 0x80_u8)
      end

      private def self.queue_audio(device : UInt32, samples : Array(Int16), resampler : AudioResampler? = nil, volume : Int32 = 100) : Nil
        return if samples.empty?
        output = resampler ? resampler.process(samples) : samples
        return if output.empty?
        output = output.map { |sample| (sample.to_i32 * volume.clamp(0, 100) // 100).to_i16 } unless volume == 100
        bytes = (output.size * sizeof(Int16)).to_u32
        maximum = resampler ? audio_max_queue_bytes(resampler.output_rate) : AUDIO_MAX_QUEUE_BYTES
        # Do not clear a live queue: it is audible as a dropout. A temporary
        # producer lead is bounded by dropping only the newest unplayed block.
        return if LibSDL.get_queued_audio_size(device) > maximum
        check(LibSDL.queue_audio(device, output.to_unsafe.as(Void*), bytes))
      end

      private def self.audio_target_bytes(sample_rate : Int32) : UInt32
        (sample_rate.to_u32 * 4_u32 // 20_u32) # 50 ms of stereo S16
      end

      private def self.audio_max_queue_bytes(sample_rate : Int32) : UInt32
        sample_rate.to_u32 * 4_u32 // 6_u32 # about 167 ms of stereo S16
      end

      private def self.handle_debug_key(scancode : Int32, repeat : UInt8, debugger : Frontend::Debugger,
                                        machine : Core::Machine, bus : Core::WonderSwanBus, audio_device : UInt32,
                                        game_id : String = "demo") : Nil
        return unless repeat == 0_u8
        case scancode
        when SC_F1
          debugger.toggle_visible
        when SC_SPACE
          debugger.toggle_pause
          LibSDL.pause_audio_device(audio_device, debugger.paused ? 1 : 0)
        when SC_N
          debugger.request_step
        when SC_1, SC_2, SC_3
          debugger.toggle_layer(bus, scancode - SC_1)
        when SC_PAGEUP
          debugger.move_memory(-8)
        when SC_PAGEDOWN
          debugger.move_memory(8)
        when SC_F5
          StateStore.default.save(machine, bus, game_id)
        when SC_F9
          StateStore.default.load(machine, bus, game_id)
          LibSDL.clear_queued_audio(audio_device)
        end
      end
    end
  end
end
