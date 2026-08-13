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

  it "reports whether an individual state slot exists" do
    root = Path["/tmp/swanium-state-exists-spec"]
    begin
      store = Swanium::Platform::StateStore.new(root)

      store.state_exists?("game", 2).should be_false
      Dir.mkdir_p(store.path("game", 2).parent)
      File.write(store.path("game", 2), "state")
      store.state_exists?("game", 2).should be_true
    ensure
      path = root / "swanium-crystal" / "states" / "game-2.swcstate"
      File.delete(path) if File.exists?(path)
      Dir.delete(root / "swanium-crystal" / "states") if Dir.exists?(root / "swanium-crystal" / "states")
      Dir.delete(root / "swanium-crystal") if Dir.exists?(root / "swanium-crystal")
      Dir.delete(root) if Dir.exists?(root)
    end
  end

  it "keeps the ten most recent existing ROM paths without duplicates" do
    root = Path["/tmp/swanium-recent-roms-spec"]
    begin
      Dir.mkdir_p(root)
      paths = 11.times.map do |index|
        path = root / "game-#{index}.wsc"
        File.write(path, "rom")
        path.to_s
      end.to_a
      store = Swanium::Platform::StateStore.new(root)

      paths.each { |path| store.record_recent_rom(path) }
      store.record_recent_rom(paths[5])

      store.recent_roms.should eq([paths[5]] + paths.reverse.first(10).reject { |path| path == paths[5] })
    ensure
      Dir.glob("#{root}/**/*").each { |path| File.delete(path) if File.file?(path) }
      Dir.delete(root / "swanium-crystal") if Dir.exists?(root / "swanium-crystal")
      Dir.delete(root) if Dir.exists?(root)
    end
  end

  it "constructs the default store from the platform root" do
    Swanium::Platform::StateStore.default.path("demo").basename.should eq("demo-0.swcstate")
  end

  it "persists user settings independently from save states" do
    root = Path["/tmp/swanium-settings-spec"]
    begin
      store = Swanium::Platform::StateStore.new(root)
      store.save_settings({"volume" => "42", "binding.a" => "29"})

      store.settings.should eq({"binding.a" => "29", "volume" => "42"})
    ensure
      File.delete(root / "swanium-crystal" / "settings.txt") if File.exists?(root / "swanium-crystal" / "settings.txt")
      Dir.delete(root / "swanium-crystal") if Dir.exists?(root / "swanium-crystal")
      Dir.delete(root) if Dir.exists?(root)
    end
  end
end
