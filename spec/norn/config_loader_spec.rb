require "spec_helper"

RSpec.describe Norn::ConfigLoader do
  before do
    # Save the original config values to restore them after each test
    @original_provider = Norn.config.llm_provider
    @original_sandbox = Norn.config.sandbox_info
  end

  after do
    # Restore config settings
    Norn::Config.config.update(
      llm_provider: @original_provider,
      sandbox_info: @original_sandbox
    )
  end

  describe ".load" do
    let(:global_yaml_content) { { provider: "gemini" } }
    let(:local_yaml_content) { { sandbox_info: "Custom project sandbox" } }

    before do
      # Clear env
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("NORN_PROVIDER").and_return(nil)
      allow(ENV).to receive(:[]).with("XDG_CONFIG_HOME").and_return(nil)

      # Stub File.exist? for XDG paths & local paths to false by default
      allow(File).to receive(:exist?).and_return(false)
    end

    it "loads default values if no files or env are present" do
      described_class.load
      expect(Norn.config.llm_provider).to eq("openai")
      expect(Norn.config.sandbox_info).to eq("You are running in a secure sandboxed CLI environment.")
    end

    it "loads and parses XDG global config and normalizes provider key" do
      global_path = File.join(Dir.home, ".config", "norn", "config.yml")
      allow(File).to receive(:exist?).with(global_path).and_return(true)
      allow(YAML).to receive(:load_file).with(global_path).and_return(global_yaml_content)

      described_class.load
      expect(Norn.config.llm_provider).to eq("gemini")
    end

    it "prefers local workspace config over global config" do
      global_path = File.join(Dir.home, ".config", "norn", "config.yml")
      local_path = File.join(Dir.pwd, ".norn.yml")

      allow(File).to receive(:exist?).with(global_path).and_return(true)
      allow(File).to receive(:exist?).with(local_path).and_return(true)

      allow(YAML).to receive(:load_file).with(global_path).and_return({ provider: "openai" })
      allow(YAML).to receive(:load_file).with(local_path).and_return({ provider: "gemini", sandbox_info: "Local custom sandbox" })

      described_class.load
      expect(Norn.config.llm_provider).to eq("gemini")
      expect(Norn.config.sandbox_info).to eq("Local custom sandbox")
    end

    it "prefers NORN_PROVIDER env variable over config files" do
      local_path = File.join(Dir.pwd, ".norn.yml")
      allow(File).to receive(:exist?).with(local_path).and_return(true)
      allow(YAML).to receive(:load_file).with(local_path).and_return({ provider: "openai" })

      allow(ENV).to receive(:[]).with("NORN_PROVIDER").and_return("gemini")

      described_class.load
      expect(Norn.config.llm_provider).to eq("gemini")
    end

    it "warns on validation failure but keeps valid properties" do
      local_path = File.join(Dir.pwd, ".norn.yml")
      allow(File).to receive(:exist?).with(local_path).and_return(true)
      allow(YAML).to receive(:load_file).with(local_path).and_return({ provider: "invalid_provider" })

      expect(described_class).to receive(:warn).with(/Norn Config Warning/i)

      described_class.load
      # Should fallback to default because validation failed
      expect(Norn.config.llm_provider).to eq("openai")
    end
  end
end
