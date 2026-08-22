require "../spec_helper"
require "../../src/swanium/platform/state_store"
require "file_utils"

describe Swanium::Platform::StateStore do
  it "derives save paths from an injected application-state root" do
    root = Path[Dir.tempdir] / "swanium-state-store-spec"
    store = Swanium::Platform::StateStore.new(root)

    store.path("My Game", 3).should eq(root / "swanium-crystal" / "states" / "My_Game" / "slot-3.swcstate")
    store.cartridge_save_path("My Game").should eq(root / "swanium-crystal" / "saves" / "My_Game.sav")
  end

  it "rejects save-state slots outside the supported UI range" do
    store = Swanium::Platform::StateStore.new(Path[Dir.tempdir] / "swanium-state-store-spec")

    expect_raises(ArgumentError, "save-state slot must be between 0 and 9") { store.path("game", 10) }
  end

  it "reports whether an individual state slot exists" do
    root = Path[Dir.tempdir] / "swanium-state-exists-spec"
    begin
      store = Swanium::Platform::StateStore.new(root)

      store.state_exists?("game", 2).should be_false
      Dir.mkdir_p(store.path("game", 2).parent)
      File.write(store.path("game", 2), Swanium::Platform::StateStore::STATE_MAGIC + "game".to_slice)
      store.state_exists?("game", 2).should be_true
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "isolates states by ROM identity and rejects a mismatched identity" do
    root = Path[Dir.tempdir] / "swanium-state-identity-spec"
    begin
      store = Swanium::Platform::StateStore.new(root)
      machine = Swanium::Core::Machine.new
      bus = Swanium::Core::WonderSwanBus.new
      store.save(machine, bus, "rom-a", 0)

      store.state_exists?("rom-a", 0).should be_true
      store.state_exists?("rom-b", 0).should be_false
      expect_raises(Swanium::Core::SaveStateError, "save state belongs to a different ROM") do
        source = store.path("rom-a", 0)
        destination = store.path("rom-b", 0)
        Dir.mkdir_p(destination.parent)
        File.rename(source, destination)
        store.load(machine, bus, "rom-b", 0)
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "keeps the ten most recent existing ROM paths without duplicates" do
    root = Path[Dir.tempdir] / "swanium-recent-roms-spec"
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
      FileUtils.rm_rf(root)
    end
  end

  it "constructs the default store from the platform root" do
    Swanium::Platform::StateStore.default.path("demo").basename.should eq("slot-0.swcstate")
  end

  it "persists user settings independently from save states" do
    root = Path[Dir.tempdir] / "swanium-settings-spec"
    begin
      store = Swanium::Platform::StateStore.new(root)
      store.save_settings({"volume" => "42", "binding.a" => "29"})

      store.settings.should eq({"binding.a" => "29", "volume" => "42"})
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "round-trips empty settings and ignores malformed lines" do
    root = Path[Dir.tempdir] / "swanium-empty-settings-spec"
    begin
      store = Swanium::Platform::StateStore.new(root)
      store.save_settings({} of String => String)

      File.read(store.settings_path).should be_empty
      store.settings.should be_empty

      File.write(store.settings_path, "\nmalformed\nvolume=42\n")
      store.settings.should eq({"volume" => "42"})
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "persists complete window positions and ignores incomplete values" do
    root = Path[Dir.tempdir] / "swanium-window-position-spec"
    begin
      store = Swanium::Platform::StateStore.new(root)

      store.window_position.should be_nil
      store.save_window_position(-120, 48)
      store.window_position.should eq({-120, 48})

      store.save_settings({"window.x" => "42"})
      store.window_position.should be_nil
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
