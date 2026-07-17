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

    describe "cascading instructions configuration with explicit clear" do
      after do
        # Clean up config state
        Norn::Config.config.update(instructions: {
          clear: [],
          base: nil,
          prepend: [],
          append: []
        })
      end

      it "merges global and local instructions, and applies granular clear correctly" do
        global_path = File.join(Dir.home, ".config", "norn", "config.yml")
        local_path = File.join(Dir.pwd, ".norn.yml")

        allow(File).to receive(:exist?).with(global_path).and_return(true)
        allow(File).to receive(:exist?).with(local_path).and_return(true)

        # Global specifies base and append
        allow(YAML).to receive(:load_file).with(global_path).and_return({
          instructions: {
            base: "you are clever",
            prepend: ["global prepend"],
            append: ["always talk in rhymes"]
          }
        })

        # Local specifies base override, prepends, and clears append and prepend
        allow(YAML).to receive(:load_file).with(local_path).and_return({
          instructions: {
            clear: ["prepend", "append"],
            base: "you are stupid",
            prepend: ["use czech"]
          }
        })

        described_class.load

        expect(Norn.config.instructions).to eq({
          clear: ["prepend", "append"],
          base: "you are stupid",
          prepend: ["use czech"], # global prepend was cleared before local prepend was added
          append: []              # global append was cleared
        })
      end

      it "works properly with JSON configuration files" do
        local_path = File.join(Dir.pwd, ".norn.json")
        allow(File).to receive(:exist?).with(local_path).and_return(true)

        json_content = '{"instructions": {"clear": ["base"], "prepend": ["from json"]}}'
        allow(File).to receive(:read).with(local_path).and_return(json_content)

        # Mock JSON parse
        allow(JSON).to receive(:parse).with(json_content).and_return({
          "instructions" => {
            "clear" => ["base"],
            "prepend" => ["from json"]
          }
        })

        described_class.load

        expect(Norn.config.instructions[:clear]).to eq(["base"])
        expect(Norn.config.instructions[:prepend]).to eq(["from json"])
      end
    end

    describe "RTK plugin configuration" do
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

      it "loads default values for RTK settings" do
        described_class.load
        expect(Norn.config.rtk_enabled).to be true
        expect(Norn.config.rtk_warn_if_missing).to be true
        expect(Norn.config.rtk_path).to be_nil
      end

      it "allows overriding and validates boolean parameters" do
        local_path = File.join(Dir.pwd, ".norn.yml")
        allow(File).to receive(:exist?).with(local_path).and_return(true)
        allow(YAML).to receive(:load_file).with(local_path).and_return({
          rtk_enabled: false,
          rtk_warn_if_missing: false,
          rtk_path: "/usr/local/bin/rtk"
        })

        described_class.load
        expect(Norn.config.rtk_enabled).to be false
        expect(Norn.config.rtk_warn_if_missing).to be false
        expect(Norn.config.rtk_path).to eq("/usr/local/bin/rtk")
      end
    end
  end
end
