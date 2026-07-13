require "spec_helper"
require "norn/modes/chat"
require "stringio"
require "dry/monads"

RSpec.describe Norn::Modes::Chat do
  include Dry::Monads[:result]

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

      io = norn_io("hello", "exit")
      chatbot = described_class.new(input: io.input, output: io.output)
      chatbot.start

      expect(io).to have_produced_in_order(
        "Norn MVP Chatbot initialized",
        "Using active provider: mock_provider",
        "You: hello",
        "Norn:",
        "Hello back!",
        "Goodbye!"
      )
      
      expect(before_called).to be(true)
      expect(after_called).to be(true)

      expect(chatbot.messages).to eq([
        { role: "user", content: "hello" },
        { role: "assistant", content: "Hello back!" }
      ])
    end

    it "uses the provided prompt for the first turn and then continues" do
      stub_llm_response("Prompt response!", provider: "mock_provider")

      io = norn_io("exit")
      chatbot = described_class.new(input: io.input, output: io.output)
      chatbot.start("my initial prompt")

      expect(io).to have_produced_in_order(
        "You: my initial prompt",
        "Prompt response!",
        "Goodbye!"
      )
      expect(chatbot.messages).to eq([
        { role: "user", content: "my initial prompt" },
        { role: "assistant", content: "Prompt response!" }
      ])
    end

    it "handles missing LLM providers gracefully" do
      Norn.config.llm_provider = "missing_provider"
      
      io = norn_io("hello", "exit")
      chatbot = described_class.new(input: io.input, output: io.output)
      chatbot.start

      expect(io).to have_produced("Error: LLM provider 'missing_provider' is not registered.")
    end
  end
end
