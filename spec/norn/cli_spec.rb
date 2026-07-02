require "spec_helper"

RSpec.describe Norn::CLI do
  describe ".register_plugins!" do
    it "triggers :on_cli_register with itself" do
      yielded_registry = nil
      Norn::PluginManager.subscribe(:on_cli_register) do |registry|
        yielded_registry = registry
      end

      described_class.register_plugins!
      expect(yielded_registry).to eq(described_class)
    end
  end

  describe ".define_mode_command" do
    it "defines a command with a positional prompt argument and provider option" do
      command_class = described_class.define_mode_command("test_mode", "A description")
      
      prompt_arg = command_class.arguments.find { |arg| arg.name == :prompt }
      expect(prompt_arg).not_to be_nil
      expect(prompt_arg.options[:required]).to be(false)

      provider_opt = command_class.options.find { |opt| opt.name == :provider }
      expect(provider_opt).not_to be_nil
    end

    it "defines a command with a boolean debug option" do
      command_class = described_class.define_mode_command("test_mode2", "A description")
      
      debug_opt = command_class.options.find { |opt| opt.name == :debug }
      expect(debug_opt).not_to be_nil
      expect(debug_opt.aliases).to include("-d")
    end

    it "calls the mode's #start method with the prompt" do
      mock_mode = double("Mode")
      mock_mode_class = double("ModeClass", new: mock_mode)
      allow(Norn::ModeRegistry).to receive(:resolve).with("test_mode").and_return(mock_mode_class)

      expect(mock_mode).to receive(:start).with("My hello prompt")

      command_class = described_class.define_mode_command("test_mode", "A description")
      command = command_class.new
      command.call(prompt: "My hello prompt")
    end
  end
end
