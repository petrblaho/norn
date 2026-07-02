require "spec_helper"
require "norn/global_options"

RSpec.describe Norn::GlobalOptions do
  before do
    described_class.clear!
  end

  after do
    # Restore standard options
    described_class.clear!
    described_class.register :provider, type: :string, aliases: ["-p"], desc: "LLM provider to use (openai, gemini)"
    described_class.register :debug, type: :boolean, aliases: ["-d"], desc: "Enable debug logging and detailed contextual error outputs"
  end

  describe ".register" do
    it "allows dynamically registering global options" do
      described_class.register(:sandbox, type: :boolean, aliases: ["-s"], desc: "Enable secure sandboxing")
      
      expect(described_class.registered_options[:sandbox]).to eq({
        type: :boolean,
        desc: "Enable secure sandboxing",
        aliases: ["-s"],
        default: nil
      })
    end
  end

  describe "ARGV Normalization algorithm" do
    # A local helper mirroring bin/norn's normalize_argv!
    def normalize_argv(argv)
      option_mappings = {}
      
      Norn::GlobalOptions.registered_options.each do |name, opt|
        option_key = "--#{name.to_s.gsub('_', '-')}"
        option_mappings[option_key] = opt[:type] == :boolean ? :boolean : :value
        (opt[:aliases] || []).each do |ali|
          option_mappings[ali] = opt[:type] == :boolean ? :boolean : :value
        end
      end

      extracted_args = []
      remaining_args = []

      i = 0
      while i < argv.size
        arg = argv[i]

        if option_mappings.key?(arg)
          if option_mappings[arg] == :value
            extracted_args << arg
            extracted_args << argv[i + 1] if i + 1 < argv.size
            i += 2
          else
            extracted_args << arg
            i += 1
          end
        else
          remaining_args << arg
          i += 1
        end
      end

      argv.replace(remaining_args + extracted_args)
    end

    before do
      described_class.clear!
      described_class.register :provider, type: :string, aliases: ["-p"], desc: "Provider"
      described_class.register :debug, type: :boolean, aliases: ["-d"], desc: "Debug"
    end

    it "shifts global value options from before subcommand to after subcommand" do
      argv = ["--provider", "gemini", "chat"]
      normalize_argv(argv)
      expect(argv).to eq(["chat", "--provider", "gemini"])
    end

    it "shifts global boolean option flags from before subcommand to after" do
      argv = ["-d", "task", "list current dir"]
      normalize_argv(argv)
      expect(argv).to eq(["task", "list current dir", "-d"])
    end

    it "handles combination of multiple global option flags and values" do
      argv = ["-p", "openai", "-d", "chat"]
      normalize_argv(argv)
      expect(argv).to eq(["chat", "-p", "openai", "-d"])
    end

    it "leaves positional parameters and subcommands completely untouched" do
      argv = ["task", "do something --provider gemini", "--provider", "gemini"]
      normalize_argv(argv)
      expect(argv).to eq(["task", "do something --provider gemini", "--provider", "gemini"])
    end
  end
end
