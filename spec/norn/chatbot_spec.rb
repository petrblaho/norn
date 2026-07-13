require "spec_helper"
require "norn/modes/chat"
require "stringio"
require "dry/monads"

RSpec.describe Norn::Modes::Chat do
  include Dry::Monads[:result]

  let(:input) { StringIO.new("hello\nexit\n") }
  let(:output) { StringIO.new }

  describe "#start" do
    it "runs the REPL loop, executes LLM call, triggers hooks, and exits" do
      stub_llm_response("Hello back!", provider: "mock_provider")

      # Trace hooks
      before_called = false
      after_called = false

      Norn::PluginManager.subscribe(:before_llm_call) do |messages|
        expect(messages.last).to eq({ role: "user", content: "hello" })
        expect(messages.first[:role]).to eq(:system)
        before_called = true
      end

      Norn::PluginManager.subscribe(:after_llm_call) do |response|
        expect(response).to eq("Hello back!")
        after_called = true
      end

      chatbot = described_class.new(input: input, output: output)
      chatbot.start

      output_str = output.string

      expect(output_str).to include("Norn MVP Chatbot initialized")
      expect(output_str).to include("Using active provider: mock_provider")
      expect(output_str).to include("You: hello")
      expect(output_str).to include("Norn:")
      expect(output_str).to include("Hello back!")
      expect(output_str).to include("Goodbye!")
      
      expect(before_called).to be(true)
      expect(after_called).to be(true)

      expect(chatbot.messages).to eq([
        { role: "user", content: "hello" },
        { role: "assistant", content: "Hello back!" }
      ])
    end

    it "uses the provided prompt for the first turn and then continues" do
      stub_llm_response("Prompt response!", provider: "mock_provider")

      chatbot = described_class.new(input: StringIO.new("exit\n"), output: output)
      chatbot.start("my initial prompt")

      output_str = output.string
      expect(output_str).to include("You: my initial prompt")
      expect(output_str).to include("Prompt response!")
      expect(output_str).to include("Goodbye!")
      expect(chatbot.messages).to eq([
        { role: "user", content: "my initial prompt" },
        { role: "assistant", content: "Prompt response!" }
      ])
    end

    it "handles missing LLM providers gracefully" do
      Norn.config.llm_provider = "missing_provider"
      
      chatbot = described_class.new(input: StringIO.new("hello\nexit\n"), output: output)
      chatbot.start

      expect(output.string).to include("Error: LLM provider 'missing_provider' is not registered.")
    end
  end
end
