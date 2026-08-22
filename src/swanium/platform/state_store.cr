require "../core/save_state"

module Swanium
  module Platform
    # Restricts save states to Swanium's own settings directory and numbered
    # slots, so arbitrary paths never enter the product UI.
    class StateStore
      STATE_MAGIC = "SWCSLOT1".to_slice
      @@default : StateStore? = nil

      def initialize(@root : Path = self.class.default_root)
      end

      def self.default : StateStore
        @@default ||= new
      end

      def path(rom_id : String = "demo", slot : Int32 = 0) : Path
        raise ArgumentError.new("save-state slot must be between 0 and 9") unless slot.in?(0..9)
        @root / "swanium-crystal" / "states" / safe_name(rom_id) / "slot-#{slot}.swcstate"
      end

      def cartridge_save_path(game_id : String) : Path
        @root / "swanium-crystal" / "saves" / "#{safe_name(game_id)}.sav"
      end

      def recent_roms_path : Path
        @root / "swanium-crystal" / "recent-roms.txt"
      end

      def settings_path : Path
        @root / "swanium-crystal" / "settings.txt"
      end

      def settings : Hash(String, String)
        source = settings_path
        return Hash(String, String).new unless File.exists?(source)
        File.read_lines(source).each_with_object(Hash(String, String).new) do |line, result|
          parts = line.split('=', 2)
          next unless parts.size == 2 && !parts[0].empty?
          result[parts[0]] = parts[1]
        end
      end

      def save_settings(values : Hash(String, String)) : Nil
        destination = settings_path
        Dir.mkdir_p(destination.parent)
        contents = values.keys.sort.map { |key| "#{key}=#{values[key]}" }.join('\n')
        contents += '\n' unless contents.empty?
        File.write(destination, contents)
      end

      # Window placement belongs with the other user preferences, rather than
      # with a particular ROM or save-state slot. Invalid or incomplete values
      # are ignored so an edited or older settings file falls back to centering.
      def window_position : Tuple(Int32, Int32)?
        values = settings
        x = values["window.x"]?.try(&.to_i?)
        y = values["window.y"]?.try(&.to_i?)
        x && y ? {x, y} : nil
      end

      def save_window_position(x : Int32, y : Int32) : Nil
        values = settings
        values["window.x"] = x.to_s
        values["window.y"] = y.to_s
        save_settings(values)
      end

      def recent_roms : Array(String)
        source = recent_roms_path
        return [] of String unless File.exists?(source)
        File.read_lines(source).map(&.strip).select { |path| !path.empty? && File.exists?(path) }.first(10)
      end

      def record_recent_rom(path : String) : Nil
        return unless File.file?(path)
        entries = recent_roms.reject { |entry| entry == path }
        entries.unshift(path)
        destination = recent_roms_path
        Dir.mkdir_p(destination.parent)
        File.write(destination, entries.first(10).join('\n') + '\n')
      end

      def clear_recent_roms : Nil
        File.delete(recent_roms_path) if File.exists?(recent_roms_path)
      end

      # The application may inspect the platform-default root while tests and
      # alternate frontends inject a different root through the initializer.
      def self.default_root : Path
        state_root = if root = ENV["XDG_STATE_HOME"]?
                       Path[root]
                     else
                       {% if flag?(:darwin) %}
                         Path.home / "Library" / "Application Support"
                       {% elsif flag?(:windows) %}
                         Path[ENV["LOCALAPPDATA"]? || (Path.home / "AppData" / "Local").to_s]
                       {% else %}
                         Path.home / ".local" / "state"
                       {% end %}
                     end
        state_root
      end

      def save(machine : Core::Machine, bus : Core::WonderSwanBus, rom_id : String, slot : Int32 = 0) : Path
        destination = path(rom_id, slot)
        payload = IO::Memory.new
        payload.write(STATE_MAGIC)
        payload.write(rom_id.to_slice)
        payload.write(Core::SaveState.dump(machine, bus))
        write_atomically(destination, payload.to_slice)
        destination
      end

      def load(machine : Core::Machine, bus : Core::WonderSwanBus, rom_id : String, slot : Int32 = 0) : Path
        source = path(rom_id, slot)
        bytes = File.read(source).to_slice
        header_size = STATE_MAGIC.size + rom_id.bytesize
        raise Core::SaveStateError.new("save state belongs to a different ROM") if bytes.size < header_size || bytes[0, STATE_MAGIC.size] != STATE_MAGIC || String.new(bytes[STATE_MAGIC.size, rom_id.bytesize]) != rom_id
        Core::SaveState.load(bytes[header_size..], machine, bus)
        source
      end

      def state_exists?(rom_id : String, slot : Int32) : Bool
        source = path(rom_id, slot)
        return false unless File.exists?(source)
        bytes = File.read(source).to_slice
        bytes.size >= STATE_MAGIC.size + rom_id.bytesize && bytes[0, STATE_MAGIC.size] == STATE_MAGIC && String.new(bytes[STATE_MAGIC.size, rom_id.bytesize]) == rom_id
      end

      def state_slot_labels(rom_id : String) : Array(String)
        10.times.map do |slot|
          source = path(rom_id, slot)
          state_exists?(rom_id, slot) ? "Slot #{slot} — #{File.info(source).modification_time.to_local.to_s("%Y-%m-%d %H:%M:%S")}" : "Slot #{slot}"
        end.to_a
      end

      def load_cartridge_save(bus : Core::WonderSwanBus, game_id : String) : Nil
        return unless bus.has_save_ram?
        source = cartridge_save_path(game_id)
        return unless File.exists?(source)
        bytes = File.read(source).to_slice
        raise ArgumentError.new("cartridge save size does not match #{game_id}") unless bytes.size == bus.save_ram_size
        bus.replace_save_ram(bytes)
      end

      def save_cartridge_save(bus : Core::WonderSwanBus, game_id : String) : Path?
        return nil unless bus.has_save_ram?
        destination = cartridge_save_path(game_id)
        write_atomically(destination, bus.save_ram_snapshot)
        destination
      end

      private def write_atomically(destination : Path, contents : Bytes) : Nil
        Dir.mkdir_p(destination.parent)
        temporary = destination.parent / ".#{destination.basename}.#{Process.pid}.tmp"
        begin
          File.write(temporary, contents)
          File.rename(temporary, destination)
        ensure
          File.delete(temporary) if File.exists?(temporary)
        end
      end

      private def safe_name(value : String) : String
        value.gsub(/[^A-Za-z0-9._-]+/, "_")
      end
    end
  end
end
