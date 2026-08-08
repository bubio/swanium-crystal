require "../src/swanium/core/machine"

# Opt-in verifier for the locally supplied public WonderSwan test ROMs.  The
# ROM images never enter the repository; this script implements only output
# protocols that have been confirmed by the upstream test sources.
module PublicRoms
  ROOT       = "/Volumes/CrucialX6/roms/WonderSwan/Tests"
  MAX_FRAMES =  120
  PASS_TILE  = 5_u8
  FAIL_TILE  = 6_u8

  record Case, name : String, path : String, markers : Array(Tuple(Int32, Int32)), model : Swanium::Core::WonderSwanModel

  def self.marker_ranges(ranges : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
    ranges.flat_map { |row, max_offset| max_offset.downto(0).map { |offset| {row, offset} } }
  end

  def self.read_markers(bus : Swanium::Core::WonderSwanBus, positions : Array(Tuple(Int32, Int32))) : Array(UInt8)
    positions.map do |row, offset|
      bus.read_u8(0x1800_u32 + row.to_u32 * 64_u32 + (27 - offset).to_u32 * 2_u32)
    end
  end

  def self.tilemap_text(bus : Swanium::Core::WonderSwanBus, base : UInt32, rows : Int32 = 32) : String
    String.build do |text|
      rows.times do |y|
        32.times do |x|
          value = bus.read_u8(base + y.to_u32 * 64_u32 + x.to_u32 * 2_u32)
          text << case value
          when 0_u8             then ' '
          when 0x20_u8..0x7e_u8 then value.chr
          else                       '.'
          end
        end
        text << '\n'
      end
    end
  end

  def self.new_machine(path : String, map_at_40000 : Bool = false, model : Swanium::Core::WonderSwanModel = Swanium::Core::WonderSwanModel::Crystal) : Tuple(Swanium::Core::Machine, Swanium::Core::WonderSwanBus)
    raise "missing public ROM: #{path}" unless File.file?(path)
    image = File.read(path)
    if map_at_40000 && image.bytesize < 0x100000
      mapped = Bytes.new(0x100000, 0_u8)
      raise "WSHWTest ROM is too large" if 0x40000 + image.bytesize > mapped.size
      mapped[0x40000, image.bytesize].copy_from(image.to_slice)
      bus = Swanium::Core::WonderSwanBus.new(mapped, model: model)
    else
      header = Swanium::Core::CartridgeHeader.parse(image.to_slice)
      bus = Swanium::Core::WonderSwanBus.new(image.to_slice,
        save_ram_size: header.save_medium.size,
        model: model,
        cartridge_header: header,
        save_ram_mapped: header.save_medium.sram?)
    end
    machine = Swanium::Core::Machine.new
    machine.cpu.reset(0xffff_u16, 0_u16)
    {machine, bus}
  end

  def self.assert_no_fault(machine : Swanium::Core::Machine, name : String) : Nil
    if opcode = machine.cpu.fault_opcode
      raise "#{name}: unsupported V30 opcode %02X" % opcode
    end
  end

  def self.run_pass_fail(case_data : Case) : Nil
    machine, bus = new_machine(case_data.path, model: case_data.model)
    markers = Array(UInt8).new(case_data.markers.size, 0_u8)
    MAX_FRAMES.times do
      machine.run_wonder_swan_frame(bus)
      markers = read_markers(bus, case_data.markers)
      break if markers.all? { |tile| tile == PASS_TILE || tile == FAIL_TILE }
    end
    assert_no_fault(machine, case_data.name)
    text = tilemap_text(bus, 0x1800_u32, case_data.markers.map(&.[0]).max + 1)
    raise "#{case_data.name}: failure markers #{markers}\n#{text}" if markers.includes?(FAIL_TILE)
    raise "#{case_data.name}: incomplete markers #{markers}\n#{text}" unless markers.all?(PASS_TILE)
    puts "PASS #{case_data.name}"
  end

  def self.run_wscputest : Nil
    path = ENV["WS_CPU_TEST_ROM"]? || "#{ROOT}/WSCpuTest/WSCpuTest.wsc"
    machine, bus = new_machine(path)
    8.times { machine.run_wonder_swan_frame(bus) }
    machine.run_wonder_swan_frame(bus, Swanium::Core::WonderSwanKey::A)
    machine.run_wonder_swan_frame(bus)
    text = ""
    (75 * 180).times do
      machine.run_wonder_swan_frame(bus)
      text = tilemap_text(bus, 0x1000_u32)
      break if text.includes?("Failed!") || (text.includes?("Ok!") && bus.read_u8(0x0136_u32) == 0_u8 && machine.cpu.halted)
    end
    assert_no_fault(machine, "WSCpuTest")
    raise "WSCpuTest failed\n#{text}" if text.includes?("Failed!")
    raise "WSCpuTest did not complete\n#{text}" unless text.includes?("Ok!") && bus.read_u8(0x0136_u32) == 0_u8 && machine.cpu.halted
    puts "PASS WSCpuTest"
  end

  def self.run_wshwtest : Nil
    machine, bus = new_machine("#{ROOT}/WSHWTest.wsc", true)
    8.times { machine.run_wonder_swan_frame(bus) }
    machine.run_wonder_swan_frame(bus, Swanium::Core::WonderSwanKey::X3)
    machine.run_wonder_swan_frame(bus)
    machine.run_wonder_swan_frame(bus, Swanium::Core::WonderSwanKey::A)
    machine.run_wonder_swan_frame(bus)
    text = ""
    (75 * 60).times do
      machine.run_wonder_swan_frame(bus)
      text = tilemap_text(bus, 0x1000_u32)
      break if text.includes?("Failed!") || (text.includes?("Sound Noise Values") && (text.includes?("Ok!") || text.includes?("Done.")))
    end
    assert_no_fault(machine, "WSHWTest")
    raise "WSHWTest failed\n#{text}" if text.includes?("Failed!")
    raise "WSHWTest did not complete\n#{text}" unless text.includes?("Sound Noise Values") && (text.includes?("Ok!") || text.includes?("Done."))
    puts "PASS WSHWTest"
  end

  def self.run_timing : Nil
    path = "#{ROOT}/WSTimingTest/timingtest.ws"
    pages = [
      {0, (1..17).to_a}, {1, (1..16).to_a}, {2, (1..16).to_a}, {3, (1..16).to_a}, {4, (1..16).to_a},
      {5, (1..16).to_a}, {6, (1..16).to_a}, {7, (1..16).to_a}, {8, (1..17).to_a}, {9, (1..16).to_a},
      {10, (1..16).to_a}, {11, (1..16).to_a}, {12, (1..16).to_a}, {13, (1..16).to_a}, {14, (1..16).to_a},
      {15, (1..16).to_a}, {16, (1..12).to_a}, {17, (1..16).to_a}, {18, (1..10).to_a}, {19, (1..16).to_a},
      {20, (1..8).to_a}, {21, (1..14).to_a}, {22, (1..9).to_a}, {23, (1..12).to_a}, {24, (1..6).to_a},
      {25, (1..12).to_a}, {26, (1..12).to_a}, {27, (1..12).to_a}, {28, (1..10).to_a},
    ]
    if requested = ENV["WS_TIMING_PAGE"]?
      page_number = requested.to_i
      pages = pages.select { |page, _| page == page_number }
      raise "WSTimingTest page out of range: #{requested}" if pages.empty?
    end
    pages.each do |page, rows|
      machine, bus = new_machine(path)
      # The program's startup code takes several frames before it reaches the
      # keypad polling loop.  Do not send page-navigation input during that
      # interval: it would be sampled only after startup and collapse multiple
      # requested page advances into one.  Page 0 is now known to pass, so its
      # completed markers are a stable readiness signal.
      180.times do
        machine.run_wonder_swan_frame(bus)
        initial = (1..17).map { |row| bus.read_u8(0x1800_u32 + row.to_u32 * 64_u32 + 48_u32) }
        break if initial.all? { |tile| tile == 'o'.ord.to_u8 || tile == 'x'.ord.to_u8 }
      end
      page.times do
        machine.run_wonder_swan_frame(bus, Swanium::Core::WonderSwanKey::X2)
        machine.run_wonder_swan_frame(bus)
        # A page runs its 1,000-iteration timing loops before returning to
        # keypad polling.  Wait for the previous marker to be cleared and the
        # newly selected page to finish before sending the next X2 press.
        cleared = false
        180.times do
          machine.run_wonder_swan_frame(bus)
          marker = bus.read_u8(0x1800_u32 + 64_u32 + 48_u32)
          cleared ||= marker != 'o'.ord.to_u8 && marker != 'x'.ord.to_u8
          break if cleared && (marker == 'o'.ord.to_u8 || marker == 'x'.ord.to_u8)
        end
      end
      markers = Array(UInt8).new(rows.size, 0_u8)
      180.times do
        machine.run_wonder_swan_frame(bus)
        markers = rows.map { |row| bus.read_u8(0x1800_u32 + row.to_u32 * 64_u32 + 48_u32) }
        break if markers.all? { |tile| tile == 'o'.ord.to_u8 || tile == 'x'.ord.to_u8 }
      end
      assert_no_fault(machine, "WSTimingTest page #{page}")
      text = tilemap_text(bus, 0x1800_u32, rows.max + 1)
      raise "WSTimingTest page #{page}: markers #{markers}\n#{text}" if markers.includes?('x'.ord.to_u8)
      raise "WSTimingTest page #{page}: incomplete markers #{markers}\n#{text}" unless markers.all?('o'.ord.to_u8)
    end
    label = ENV["WS_TIMING_PAGE"]? ? "page #{ENV["WS_TIMING_PAGE"]}" : "pages 0-28"
    puts "PASS WSTimingTest #{label}"
  end

  def self.run : Nil
    run_wscputest
    cases = [
      Case.new("cpu/80186_quirks", "#{ROOT}/ws-test-suite/mono/cpu/80186_quirks.ws", marker_ranges([{0, 0}, {1, 0}, {2, 0}]), Swanium::Core::WonderSwanModel::Mono),
      Case.new("cpu/prefixes", "#{ROOT}/ws-test-suite/mono/cpu/prefixes.ws", marker_ranges([{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}, {6, 0}]), Swanium::Core::WonderSwanModel::Mono),
      Case.new("soc/interrupts", "#{ROOT}/ws-test-suite/mono/soc/interrupts.ws", marker_ranges([{0, 7}, {1, 4}]), Swanium::Core::WonderSwanModel::Mono),
      Case.new("cpu/interrupt_timing", "#{ROOT}/ws-test-suite/mono/cpu/interrupt_timing.ws", marker_ranges((0..14).map { |row| {row, 0} }), Swanium::Core::WonderSwanModel::Mono),
      Case.new("rtc/mapper", "#{ROOT}/ws-test-suite/mono/rtc/mapper.ws", [{0, 1}, {0, 0}, {1, 1}, {1, 0}, {2, 1}, {2, 0}, {3, 1}, {3, 0}, {4, 1}, {4, 0}, {5, 1}, {5, 0}, {6, 1}, {6, 0}, {7, 1}, {7, 0}, {8, 1}, {8, 0}, {9, 1}, {9, 0}, {10, 1}, {10, 0}, {11, 1}, {11, 0}, {12, 1}, {13, 1}, {13, 0}], Swanium::Core::WonderSwanModel::Mono),
      Case.new("display/mono_palettes_writemask", "#{ROOT}/ws-test-suite/mono/display/mono_palettes_writemask.ws", marker_ranges((0..15).map { |row| {row, 1} }), Swanium::Core::WonderSwanModel::Mono),
      Case.new("sound/quirks", "#{ROOT}/ws-test-suite/mono/sound/quirks.ws", marker_ranges([{0, 2}, {1, 0}, {2, 2}, {3, 0}, {4, 1}, {5, 2}, {6, 3}, {7, 1}, {8, 0}]), Swanium::Core::WonderSwanModel::Mono),
      Case.new("eeprom/cartridge_1kbit", "#{ROOT}/ws-test-suite/mono/eeprom/cartridge_1kbit.ws", [{1, 0}, {2, 1}, {2, 0}, {3, 1}, {3, 0}, {3, 3}, {4, 1}, {4, 0}, {4, 3}, {5, 1}, {5, 0}, {6, 0}, {7, 0}, {8, 0}, {8, 1}, {8, 2}, {8, 3}, {8, 4}, {8, 5}, {8, 6}, {8, 7}, {8, 8}, {8, 9}, {8, 10}, {8, 11}, {10, 0}, {10, 1}, {10, 2}, {10, 3}, {10, 4}], Swanium::Core::WonderSwanModel::Mono),
      Case.new("dma/alignment_access", "#{ROOT}/ws-test-suite/color/dma/alignment_access.wsc", marker_ranges([{0, 2}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}]), Swanium::Core::WonderSwanModel::Crystal),
      Case.new("dma/gdma_timing", "#{ROOT}/ws-test-suite/color/dma/gdma_timing.wsc", marker_ranges((0..12).map { |row| {row, 0} }), Swanium::Core::WonderSwanModel::Crystal),
      Case.new("dma/sound_dma", "#{ROOT}/ws-test-suite/color/dma/sound_dma.wsc", marker_ranges([{0, 1}, {1, 1}, {2, 0}, {3, 0}, {4, 0}, {5, 0}, {6, 0}, {7, 4}, {8, 4}, {9, 1}, {10, 0}]), Swanium::Core::WonderSwanModel::Crystal),
    ]
    cases.each { |case_data| run_pass_fail(case_data) }
    run_timing
    run_wshwtest
  end
end

PublicRoms.run
