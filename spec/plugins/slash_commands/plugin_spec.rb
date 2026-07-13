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

    it "intercepts /tools to return a list of registered tools" do
      # Mock a registered tool
      mock_tool = Norn::Tool.new("test_introspection_tool", "Introspective test tool", {}, required_capabilities: [:sys_read])
      allow(Norn::ToolRegistry).to receive(:registered_tools).and_return([mock_tool])

      payload = { text: "/tools", action: :continue, mode: nil }
      result = plugin.on_user_input(payload)

      expect(result).to be_success
      expect(result.value![:action]).to eq(:skip)
      expect(result.value![:output]).to include("test_introspection_tool")
      expect(result.value![:output]).to include("Introspective test tool")
    end

    it "intercepts /session to return session statistics when session is active" do
      mock_session = double("Session", stats: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150, tool_calls: 5 })
      allow(Norn).to receive(:[]).with("session").and_return(mock_session)

      payload = { text: "/session", action: :continue, mode: nil }
      result = plugin.on_user_input(payload)

      expect(result).to be_success
      expect(result.value![:action]).to eq(:skip)
      expect(result.value![:output]).to include("Current Session Stats")
      expect(result.value![:output]).to include("Prompt Tokens:     100")
      expect(result.value![:output]).to include("Completion Tokens: 50")
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
