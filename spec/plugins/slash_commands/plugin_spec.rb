require "spec_helper"
require_relative "../../../plugins/slash_commands/plugin"
require "norn/plugin_manager"

RSpec.describe Norn::Plugins::SlashCommands::SlashCommandsPlugin do
  let(:plugin) { described_class.new }

  describe "#on_user_input" do
    it "intercepts exit and quit to return :exit action" do
      ["exit", "quit", "/exit", "/quit"].each do |cmd|
        payload = { text: cmd, action: :continue, mode: nil }
        result = plugin.on_user_input(payload)
        
        expect(result).to be_success
        expect(result.value![:action]).to eq(:exit)
      end
    end

    it "intercepts /help to return :skip action and help output" do
      payload = { text: "/help", action: :continue, mode: nil }
      result = plugin.on_user_input(payload)

      expect(result).to be_success
      expect(result.value![:action]).to eq(:skip)
      expect(result.value![:output]).to include("Norn Slash Commands:")
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

    it "leaves ordinary user prompts completely untouched" do
      payload = { text: "how to design slash commands?", action: :continue, mode: nil }
      result = plugin.to_h rescue plugin.on_user_input(payload) # safely call on_user_input

      expect(result).to be_success
      expect(result.value![:action]).to eq(:continue)
      expect(result.value![:text]).to eq("how to design slash commands?")
    end
  end
end
