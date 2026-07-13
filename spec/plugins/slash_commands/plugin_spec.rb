require "spec_helper"

RSpec.describe Norn::Plugins::SlashCommands::SlashCommandsPlugin, norn_plugins: :slash_commands do
  let(:plugin) { norn_plugin(:slash_commands) }

  describe "#on_user_input with built-ins" do
    it "intercepts exit and quit to return :exit action" do
      ["exit", "quit", "/exit", "/quit"].each do |cmd|
        payload = { text: cmd, action: :continue, mode: nil }
        result = plugin.on_user_input(payload)
        
        expect(result).to be_success
        expect(result.value![:action]).to eq(:exit)
      end
    end

    it "intercepts /help to return :skip action and dynamically listed help output" do
      payload = { text: "/help", action: :continue, mode: nil }
      result = plugin.on_user_input(payload)

      expect(result).to be_success
      expect(result.value![:action]).to eq(:skip)
      expect(result.value![:output]).to include("Norn Slash Commands:")
      expect(result.value![:output]).to include("/exit")
      expect(result.value![:output]).to include("/clear")
    end

    it "intercepts /clear or /reset, clears messages, and clears session if registered" do
      mock_messages = ["msg1", "msg2"]
      mock_mode = double("Mode", messages: mock_messages)
      mock_session = double("Session")
      allow(Norn).to receive(:[]).with("session").and_return(mock_session)
      expect(mock_session).to receive(:clear!)

      payload = { text: "/clear", action: :continue, mode: mock_mode }
      result = plugin.on_user_input(payload)

      expect(result).to be_success
      expect(result.value![:action]).to eq(:skip)
      expect(result.value![:output]).to include("Session and conversation history cleared")
      expect(mock_messages).to be_empty
    end
  end

  describe "extensible slash command registration" do
    it "allows other plugins to register custom commands via the hook" do
      # Subscribe to the registration hook to simulate another plugin registering a command
      Norn::PluginManager.subscribe(:on_slash_commands_register) do |registry|
        registry.register("/my_cmd", "Custom command description") do |payload|
          Dry::Monads::Success(payload.merge(action: :skip, output: "Custom executed!"))
        end
      end

      # Re-initialize the plugin to trigger registration hooks
      ext_plugin = described_class.new

      # 1. Test running the custom command
      payload = { text: "/my_cmd", action: :continue, mode: nil }
      result = ext_plugin.on_user_input(payload)

      expect(result).to be_success
      expect(result.value![:action]).to eq(:skip)
      expect(result.value![:output]).to eq("Custom executed!")

      # 2. Test that it dynamically appears in the /help output!
      help_payload = { text: "/help", action: :continue, mode: nil }
      help_result = ext_plugin.on_user_input(help_payload)

      expect(help_result.value![:output]).to include("/my_cmd")
      expect(help_result.value![:output]).to include("Custom command description")
    end
  end
end
