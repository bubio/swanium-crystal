require "../core/save_state"

module Swanium
  module Platform
    # Restricts save states to Swanium's own settings directory and numbered
    # slots, so arbitrary paths never enter the product UI.
    module StateStore
      def self.path(game_id : String = "demo", slot : Int32 = 0) : Path
        raise ArgumentError.new("save-state slot must be between 0 and 9") unless slot.in?(0..9)
        state_root / "swanium-crystal" / "states" / "#{safe_name(game_id)}-#{slot}.swcstate"
      end

      def self.cartridge_save_path(game_id : String) : Path
        state_root / "swanium-crystal" / "saves" / "#{safe_name(game_id)}.sav"
      end

      private def self.state_root : Path
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

      def self.save(machine : Core::Machine, bus : Core::WonderSwanBus, game_id : String = "demo", slot : Int32 = 0) : Path
        destination = path(game_id, slot)
        write_atomically(destination, Core::SaveState.dump(machine, bus))
        destination
      end

      def self.load(machine : Core::Machine, bus : Core::WonderSwanBus, game_id : String = "demo", slot : Int32 = 0) : Path
        source = path(game_id, slot)
        Core::SaveState.load(File.read(source).to_slice, machine, bus)
        source
      end

      def self.load_cartridge_save(bus : Core::WonderSwanBus, game_id : String) : Nil
        return unless bus.has_save_ram?
        source = cartridge_save_path(game_id)
        return unless File.exists?(source)
        bytes = File.read(source).to_slice
        raise ArgumentError.new("cartridge save size does not match #{game_id}") unless bytes.size == bus.save_ram_size
        bus.replace_save_ram(bytes)
      end

      def self.save_cartridge_save(bus : Core::WonderSwanBus, game_id : String) : Path?
        return nil unless bus.has_save_ram?
        destination = cartridge_save_path(game_id)
        write_atomically(destination, bus.save_ram_snapshot)
        destination
      end

      private def self.write_atomically(destination : Path, contents : Bytes) : Nil
        Dir.mkdir_p(destination.parent)
        temporary = destination.parent / ".#{destination.basename}.#{Process.pid}.tmp"
        begin
          File.write(temporary, contents)
          File.rename(temporary, destination)
        ensure
          File.delete(temporary) if File.exists?(temporary)
        end
      end

      private def self.safe_name(value : String) : String
        value.gsub(/[^A-Za-z0-9._-]+/, "_")
      end
    end
  end
end
