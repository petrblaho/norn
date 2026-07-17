require "spec_helper"
require_relative "../../../plugins/rtk/plugin"

RSpec.describe Norn::Plugins::Rtk::RtkPlugin do
  let(:plugin) { described_class.new }

  before do
    @orig_enabled = Norn.config.rtk_enabled
    @orig_warn = Norn.config.rtk_warn_if_missing
    @orig_path = Norn.config.rtk_path
  end

  after do
    Norn::Config.config.update(
      rtk_enabled: @orig_enabled,
      rtk_warn_if_missing: @orig_warn,
      rtk_path: @orig_path
    )
  end

  describe "Plugin initialization and binary detection" do
    context "when rtk is present" do
      before do
        allow_any_instance_of(described_class).to receive(:check_rtk_available).and_return(true)
      end

      it "does not emit warning and responds to execute hook" do
        expect(described_class).not_to receive(:warn)
        p = described_class.new
        expect(p.respond_to?(:before_subprocess_execute)).to be true
      end
    end

    context "when rtk is missing" do
      before do
        allow_any_instance_of(described_class).to receive(:check_rtk_available).and_return(false)
      end

      it "emits a warning and disables hook response if warn_if_missing is true" do
        Norn::Config.config.update(rtk_enabled: true, rtk_warn_if_missing: true)
        expect_any_instance_of(described_class).to receive(:warn).with(/rtk binary not found/)
        p = described_class.new
        expect(p.respond_to?(:before_subprocess_execute)).to be false
      end

      it "does not emit a warning but disables hook response if warn_if_missing is false" do
        Norn::Config.config.update(rtk_enabled: true, rtk_warn_if_missing: false)
        expect_any_instance_of(described_class).not_to receive(:warn)
        p = described_class.new
        expect(p.respond_to?(:before_subprocess_execute)).to be false
      end
    end
  end

  describe "#before_subprocess_execute" do
    let(:payload) { { command: "git status" } }

    before do
      allow_any_instance_of(described_class).to receive(:check_rtk_available).and_return(true)
    end

    context "when rtk successfully rewrites a command" do
      it "returns payload with rewritten command" do
        expect(Open3).to receive(:capture3)
          .with("rtk", "rewrite", "git status")
          .and_return(["rtk git status", "", double(success?: true)])

        result = plugin.before_subprocess_execute(payload)
        expect(result[:command]).to eq("rtk git status")
      end
    end

    context "when rtk output is the same as input" do
      it "returns the original untouched payload" do
        expect(Open3).to receive(:capture3)
          .with("rtk", "rewrite", "git status")
          .and_return(["git status", "", double(success?: true)])

        result = plugin.before_subprocess_execute(payload)
        expect(result[:command]).to eq("git status")
      end
    end

    context "when rtk command execution fails" do
      it "gracefully returns the original payload" do
        expect(Open3).to receive(:capture3)
          .with("rtk", "rewrite", "git status")
          .and_raise(RuntimeError.new("Binary crashed"))

        result = plugin.before_subprocess_execute(payload)
        expect(result[:command]).to eq("git status")
      end
    end
  end
end
