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
      CONTROLLER_BUTTON_OPTIONS = [
        {"A", 0}, {"B", 1}, {"X", 2}, {"Y", 3}, {"Back", 4}, {"Start", 6},
        {"Left Shoulder", 9}, {"Right Shoulder", 10},
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

      def controller_button(action : Symbol) : Int32
        defaults = {a: 0, b: 1, start: 6}
        Platform::StateStore.default.settings["controller.#{action}"]?.try(&.to_i?).try(&.clamp(0, 20)) || defaults[action]
      end

      def set_controller_button(action : Symbol, button : Int32) : Nil
        raise ArgumentError.new("unknown controller action: #{action}") unless [:a, :b, :start].includes?(action)
        settings = Platform::StateStore.default.settings
        settings["controller.#{action}"] = button.to_s
        Platform::StateStore.default.save_settings(settings)
      end

      def controller_enabled?(name : String, default : Bool = true) : Bool
        Platform::StateStore.default.settings["controller.#{name}"]?.try { |value| value == "true" } || default
      end

      def set_controller_enabled(name : String, enabled : Bool) : Nil
        settings = Platform::StateStore.default.settings
        settings["controller.#{name}"] = enabled.to_s
        Platform::StateStore.default.save_settings(settings)
      end

      def self.controller_button_names : Array(String)
        CONTROLLER_BUTTON_OPTIONS.map(&.[0])
      end

      def self.controller_button_index(button : Int32) : Int32
        CONTROLLER_BUTTON_OPTIONS.index { |option| option[1] == button }.try(&.to_i) || 0
      end

      def self.controller_button_value(index : Int32) : Int32
        CONTROLLER_BUTTON_OPTIONS[index.clamp(0, CONTROLLER_BUTTON_OPTIONS.size - 1)][1]
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
