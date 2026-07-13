require "spec_helper"
require "norn/modes/dev"
require "dry/monads"

RSpec.describe Norn::Modes::Dev do
  include Dry::Monads[:result]

  let(:io) { norn_io("exit") }
  let(:dev_mode) { described_class.new(input: io.input, output: io.output) }

  it "is successfully registered as 'dev' in the ModeRegistry" do
    expect(Norn::ModeRegistry.resolve("dev")).to eq(described_class)
  end

  it "is classified as an interactive mode" do
    expect(dev_mode.interactive?).to be(true)
  end

  it "has full capabilities authorized (read, write, execute, vcs, net)" do
    expect(dev_mode.allowed_capabilities).to eq([
      :sys_read, :sys_write, :sys_execute, :vcs_read, :vcs_write, :net_egress
    ])
  end

  describe "#start REPL loop" do
    it "initializes, prints pairing banner, reads input, and exits cleanly" do
      result = dev_mode.start

      expect(result).to be_success
      expect(io).to have_produced_in_order(
        "Norn Live Developer Pairing Mode initialized",
        "Goodbye!"
      )
    end
  end
end
