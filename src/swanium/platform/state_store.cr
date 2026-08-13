require "../core/save_state"

module Swanium
  module Platform
    # Restricts save states to Swanium's own settings directory and numbered
    # slots, so arbitrary paths never enter the product UI.
    class StateStore
      @@default : StateStore? = nil

      def initialize(@root : Path = self.class.default_root)
      end

      def self.default : StateStore
        @@default ||= new
      end

      def path(game_id : String = "demo", slot : Int32 = 0) : Path
        raise ArgumentError.new("save-state slot must be between 0 and 9") unless slot.in?(0..9)
        @root / "swanium-crystal" / "states" / "#{safe_name(game_id)}-#{slot}.swcstate"
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
          key, value = line.split('=', 2)
          result[key] = value if value
        end
      end

      def save_settings(values : Hash(String, String)) : Nil
        destination = settings_path
        Dir.mkdir_p(destination.parent)
        File.write(destination, values.keys.sort.map { |key| "#{key}=#{values[key]}" }.join('\n') + '\n')
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
                       {% else %}
                         Path.home / ".local" / "state"
                       {% end %}
                     end
        state_root
      end

      def save(machine : Core::Machine, bus : Core::WonderSwanBus, game_id : String = "demo", slot : Int32 = 0) : Path
        destination = path(game_id, slot)
        write_atomically(destination, Core::SaveState.dump(machine, bus))
        destination
      end

      def load(machine : Core::Machine, bus : Core::WonderSwanBus, game_id : String = "demo", slot : Int32 = 0) : Path
        source = path(game_id, slot)
        Core::SaveState.load(File.read(source).to_slice, machine, bus)
        source
      end

      def state_exists?(game_id : String, slot : Int32) : Bool
        File.exists?(path(game_id, slot))
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
