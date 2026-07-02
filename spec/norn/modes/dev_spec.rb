require "spec_helper"
require "norn/modes/dev"
require "stringio"
require "dry/monads"

RSpec.describe Norn::Modes::Dev do
  include Dry::Monads[:result]

  let(:input) { StringIO.new("exit\n") }
  let(:output) { StringIO.new }

  let(:dev_mode) { described_class.new(input: input, output: output) }

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
      expect(output.string).to include("Norn Live Developer Pairing Mode initialized")
      expect(output.string).to include("Goodbye!")
    end
  end
end
