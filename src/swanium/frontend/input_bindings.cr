require "../platform/state_store"

module Swanium
  module Frontend
    # Keyboard bindings are SDL scancodes, so they remain layout-independent.
    class InputBindings
      ACTIONS  = [:x1, :x2, :x3, :x4, :y1, :y2, :y3, :y4, :a, :b, :start]
      DEFAULTS = {
        x1: 82, x2: 79, x3: 81, x4: 80,
        y1: 26, y2: 7, y3: 22, y4: 4,
        a: 27, b: 29, start: 40,
      }
      OPTIONS = [
        {"Arrow Up", 82}, {"Arrow Right", 79}, {"Arrow Down", 81}, {"Arrow Left", 80},
        {"W", 26}, {"A", 4}, {"S", 22}, {"D", 7},
        {"X", 27}, {"Z", 29}, {"Return", 40}, {"Space", 44},
      ]

      @@default : InputBindings? = nil

      def self.default : InputBindings
        @@default ||= new
      end

      def initialize
        @scancodes = Hash(Symbol, Int32).new
        ACTIONS.each { |action| @scancodes[action] = DEFAULTS[action] }
        load
      end

      def scancode(action : Symbol) : Int32
        @scancodes[action]
      end

      def set(action : Symbol, scancode : Int32) : Nil
        raise ArgumentError.new("unknown input action: #{action}") unless ACTIONS.includes?(action)
        @scancodes[action] = scancode
        save
      end

      def self.action_label(action : Symbol) : String
        {
          x1: "X pad Up", x2: "X pad Right", x3: "X pad Down", x4: "X pad Left",
          y1: "Y pad Up", y2: "Y pad Right", y3: "Y pad Down", y4: "Y pad Left",
          a: "A button", b: "B button", start: "Start",
        }[action]
      end

      def self.option_names : Array(String)
        OPTIONS.map(&.[0])
      end

      def self.option_index(scancode : Int32) : Int32
        OPTIONS.index { |option| option[1] == scancode }.try(&.to_i) || 0
      end

      def self.option_scancode(index : Int32) : Int32
        OPTIONS[index.clamp(0, OPTIONS.size - 1)][1]
      end

      private def load : Nil
        Platform::StateStore.default.settings.each do |key, value|
          next unless key.starts_with?("binding.")
          action = ACTIONS.find { |candidate| candidate.to_s == key[8..] }
          scancode = value.to_i?
          @scancodes[action] = scancode if action && scancode && scancode >= 0
        end
      end

      private def save : Nil
        settings = Platform::StateStore.default.settings
        ACTIONS.each { |action| settings["binding.#{action}"] = @scancodes[action].to_s }
        Platform::StateStore.default.save_settings(settings)
      end
    end
  end
end
