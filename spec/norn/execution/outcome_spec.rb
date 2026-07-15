require "spec_helper"
require_relative "../../../lib/norn/execution/outcome"

RSpec.describe Norn::Execution::Outcome do
  describe "#success? and #failure?" do
    it "returns true for success? when exit code is 0" do
      outcome = described_class.new(stdout: "ok", exit_code: 0)
      expect(outcome.success?).to be(true)
      expect(outcome.failure?).to be(false)
    end

    it "returns true for failure? when exit code is non-zero" do
      outcome = described_class.new(stderr: "error", exit_code: 1)
      expect(outcome.success?).to be(false)
      expect(outcome.failure?).to be(true)
    end
  end

  describe "#+ (Monoid Addition)" do
    it "merges stdout, stderr, and aggregates the exit code sequentially" do
      out1 = described_class.new(stdout: "step 1", stderr: "", exit_code: 0)
      out2 = described_class.new(stdout: "step 2", stderr: "warning", exit_code: 1)
      
      combined = out1 + out2
      expect(combined.stdout).to eq("step 1\nstep 2")
      expect(combined.stderr).to eq("warning")
      expect(combined.exit_code).to eq(1)
    end
  end

  describe "#to_s" do
    it "returns stdout if successful" do
      outcome = described_class.new(stdout: "good", exit_code: 0)
      expect(outcome.to_s).to eq("good")
    end

    it "returns detailed stderr and stdout if failed" do
      outcome = described_class.new(stdout: "partial", stderr: "bad", exit_code: 2)
      expect(outcome.to_s).to include("Execution Failed (exit code 2):")
      expect(outcome.to_s).to include("bad")
      expect(outcome.to_s).to include("partial")
    end
  end
end
