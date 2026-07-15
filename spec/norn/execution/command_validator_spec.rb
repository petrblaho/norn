require "spec_helper"
require_relative "../../../lib/norn/execution/command_validator"

RSpec.describe Norn::Execution::CommandValidator do
  describe ".validate!" do
    it "allows safe execution commands" do
      expect { described_class.validate!("git status") }.not_to raise_error
      expect { described_class.validate!("bundle exec rspec spec") }.not_to raise_error
      expect { described_class.validate!("echo 'hello'") }.not_to raise_error
    end

    it "blocks sudo actions to prevent privilege escalation" do
      expect {
        described_class.validate!("sudo apt-get install git")
      }.to raise_error(SecurityError, /escalation/)
    end

    it "blocks destructive rm -rf / commands" do
      expect {
        described_class.validate!("rm -rf /")
      }.to raise_error(SecurityError, /destructive/)
    end

    it "blocks destructive rm -rf * commands" do
      expect {
        described_class.validate!("rm -rf *")
      }.to raise_error(SecurityError, /destructive/)
    end

    it "blocks direct raw disk write utilities" do
      expect {
        described_class.validate!("dd if=/dev/zero of=/dev/sda")
      }.to raise_error(SecurityError, /destructive/)
    end
  end
end
