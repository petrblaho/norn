require "spec_helper"
require "stringio"
require "norn/ui/gatekeeper"

RSpec.describe Norn::UI::Gatekeeper do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  subject { described_class.new(input: input, output: output) }

  describe "#authorize_capabilities" do
    it "returns true when user selects Yes" do
      # Simulate selecting Yes in tty-prompt select (usually first option/index)
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(true)
      result = subject.authorize_capabilities("file_write", [:sys_write], { path: "test.txt" })
      expect(result).to be true
      expect(output.string).to include("Security Escalation")
    end

    it "returns false when user selects No" do
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(false)
      result = subject.authorize_capabilities("file_write", [:sys_write], { path: "test.txt" })
      expect(result).to be false
    end
  end
end
