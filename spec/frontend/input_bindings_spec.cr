require "../spec_helper"
require "../../src/swanium/frontend/input_bindings"

describe Swanium::Frontend::InputBindings do
  describe ".option_name" do
    it "labels SDL letter scancodes outside the default bindings" do
      Swanium::Frontend::InputBindings.option_name(18).should eq("O")
      Swanium::Frontend::InputBindings.option_name(15).should eq("L")
    end

    it "labels SDL number scancodes" do
      Swanium::Frontend::InputBindings.option_name(30).should eq("1")
      Swanium::Frontend::InputBindings.option_name(39).should eq("0")
    end
  end
end
