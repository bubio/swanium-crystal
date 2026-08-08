require "../spec_helper"
require "../../src/swanium/platform/state_store"

describe Swanium::Platform::StateStore do
  it "derives save paths from an injected application-state root" do
    store = Swanium::Platform::StateStore.new(Path["/tmp/swanium-state-store-spec"])

    store.path("My Game", 3).should eq(Path["/tmp/swanium-state-store-spec/swanium-crystal/states/My_Game-3.swcstate"])
    store.cartridge_save_path("My Game").should eq(Path["/tmp/swanium-state-store-spec/swanium-crystal/saves/My_Game.sav"])
  end

  it "rejects save-state slots outside the supported UI range" do
    store = Swanium::Platform::StateStore.new(Path["/tmp/swanium-state-store-spec"])

    expect_raises(ArgumentError, "save-state slot must be between 0 and 9") { store.path("game", 10) }
  end

  it "constructs the default store from the platform root" do
    Swanium::Platform::StateStore.default.path("demo").basename.should eq("demo-0.swcstate")
  end
end
