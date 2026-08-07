require "../core/save_state"

module Swanium
  module Platform
    # Restricts save states to Swanium's own settings directory and numbered
    # slots, so arbitrary paths never enter the product UI.
    module StateStore
      def self.path(slot : Int32 = 0) : Path
        raise ArgumentError.new("save-state slot must be between 0 and 9") unless slot.in?(0..9)
        state_root = if root = ENV["XDG_STATE_HOME"]?
                       Path[root]
                     else
                       {% if flag?(:darwin) %}
                         Path.home / "Library" / "Application Support"
                       {% else %}
                         Path.home / ".local" / "state"
                       {% end %}
                     end
        state_root / "swanium-crystal" / "states" / "demo-#{slot}.swcstate"
      end

      def self.save(machine : Core::Machine, bus : Core::WonderSwanBus, slot : Int32 = 0) : Path
        destination = path(slot)
        Dir.mkdir_p(destination.parent)
        File.write(destination, Core::SaveState.dump(machine, bus))
        destination
      end

      def self.load(machine : Core::Machine, bus : Core::WonderSwanBus, slot : Int32 = 0) : Path
        source = path(slot)
        Core::SaveState.load(File.read(source).to_slice, machine, bus)
        source
      end
    end
  end
end
