require "../spec_helper"

describe Swanium::Core::Machine do
  it "advances deterministically by the requested cycle count" do
    machine = Swanium::Core::Machine.new

    machine.run_cycles(12_u32)
    machine.run_cycles(30_u32)

    machine.cycles.should eq(42_u64)
  end
end
