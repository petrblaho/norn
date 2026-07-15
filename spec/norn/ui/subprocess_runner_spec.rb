require "spec_helper"
require_relative "../../../lib/norn/ui/subprocess_runner"

RSpec.describe Norn::UI::SubprocessRunner do
  describe ".run" do
    it "runs a successful system command and captures stdout" do
      outcome = described_class.run("echo 'hello world'")
      expect(outcome.success?).to be(true)
      expect(outcome.stdout.strip).to eq("hello world")
      expect(outcome.stderr).to eq("")
    end

    it "runs a failing command and captures stderr and non-zero exit code" do
      outcome = described_class.run("ruby -e 'warn \"my error\"; exit 5'")
      expect(outcome.success?).to be(false)
      expect(outcome.exit_code).to eq(5)
      expect(outcome.stderr.strip).to eq("my error")
    end

    it "yields stdout/stderr chunks in real-time if a block is provided" do
      yielded_chunks = []
      described_class.run("echo 'realtime'") do |stream_type, chunk|
        yielded_chunks << [stream_type, chunk.strip]
      end

      expect(yielded_chunks).to include([:stdout, "realtime"])
    end

    it "handles command not found gracefully and returns exit code 127" do
      outcome = described_class.run("notarealcommandexecuting")
      expect(outcome.success?).to be(false)
      expect(outcome.exit_code).to eq(127)
      expect(outcome.stderr).to include("command not found")
    end
  end
end
