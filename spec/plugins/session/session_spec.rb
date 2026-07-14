require "spec_helper"
require_relative "../../../plugins/session/session"

RSpec.describe Norn::Session do
  let(:session) { described_class.new }

  describe "#initialize and #clear!" do
    it "sets up an empty state with default values" do
      expect(session.get(:prompt_tokens)).to eq(0)
      expect(session.get(:completion_tokens)).to eq(0)
      expect(session.get(:total_tokens)).to eq(0)
      expect(session.get(:provider_usage)).to eq({})
      expect(session.get(:tool_calls)).to eq([])
      expect(session.get(:history)).to eq([])
      expect(session.get(:metadata)).to eq({})
      expect(session.get(:session_approvals)).to eq([])
    end
  end

  describe "#set and #get" do
    it "allows setting and getting key-value pairs" do
      session.set(:foo, "bar")
      expect(session.get(:foo)).to eq("bar")
    end

    it "handles symbol keys consistently" do
      session.set("string_key", 123)
      expect(session.get(:string_key)).to eq(123)
    end
  end

  describe "#increment" do
    it "increments an existing numeric value" do
      session.set(:counter, 10)
      session.increment(:counter, 5)
      expect(session.get(:counter)).to eq(15)
    end

    it "initializes and increments a non-existent value" do
      session.increment(:new_counter, 3)
      expect(session.get(:new_counter)).to eq(3)
    end
  end

  describe "#append" do
    it "appends an item to an existing array" do
      session.set(:list, [1, 2])
      session.append(:list, 3)
      expect(session.get(:list)).to eq([1, 2, 3])
    end

    it "initializes and appends to a non-existent array" do
      session.append(:new_list, "first")
      expect(session.get(:new_list)).to eq(["first"])
    end
  end

  describe "#record_tokens" do
    it "updates total and provider-specific token usage" do
      session.record_tokens(prompt: 10, completion: 20, provider: "openai", model: "gpt_4o")

      expect(session.get(:prompt_tokens)).to eq(10)
      expect(session.get(:completion_tokens)).to eq(20)
      expect(session.get(:total_tokens)).to eq(30)

      provider_usage = session.get(:provider_usage)
      expect(provider_usage[:openai][:gpt_4o]).to eq({
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      })
    end

    it "aggregates tokens on subsequent calls" do
      session.record_tokens(prompt: 10, completion: 20, provider: "openai", model: "gpt_4o")
      session.record_tokens(prompt: 5, completion: 15, provider: "openai", model: "gpt_4o")

      expect(session.get(:prompt_tokens)).to eq(15)
      expect(session.get(:completion_tokens)).to eq(35)
      expect(session.get(:total_tokens)).to eq(50)

      provider_usage = session.get(:provider_usage)
      expect(provider_usage[:openai][:gpt_4o]).to eq({
        prompt_tokens: 15,
        completion_tokens: 35,
        total_tokens: 50
      })
    end
  end

  describe "#record_tool_call" do
    it "records a tool call with a timestamp" do
      session.record_tool_call(tool_name: "glob", arguments: { pattern: "*.rb" }, result: "success")

      tool_calls = session.get(:tool_calls)
      expect(tool_calls.size).to eq(1)
      expect(tool_calls.first[:tool]).to eq("glob")
      expect(tool_calls.first[:arguments]).to eq({ pattern: "*.rb" })
      expect(tool_calls.first[:result]).to eq("success")
      expect(tool_calls.first[:timestamp]).to be_a(Time)
    end
  end

  describe "#record_message" do
    it "records a conversational message" do
      session.record_message(role: "user", content: "hello")

      history = session.get(:history)
      expect(history.size).to eq(1)
      expect(history.first[:role]).to eq("user")
      expect(history.first[:content]).to eq("hello")
      expect(history.first[:timestamp]).to be_a(Time)
    end
  end

  describe "#to_h" do
    it "returns a deep copy of the state" do
      session.set(:metadata, { nested: { value: 42 } })
      data = session.to_h

      expect(data[:metadata][:nested][:value]).to eq(42)

      # Mutate returned hash to verify it is deep-copied and does not affect session store
      data[:metadata][:nested][:value] = 99
      expect(session.get(:metadata)[:nested][:value]).to eq(42)
    end

    it "ensures all strings in the copy are converted to valid UTF-8 and not BINARY" do
      binary_str = "hello \xFF".b
      session.set(:binary_key, binary_str)

      data = session.to_h
      copied_str = data[:binary_key]

      expect(copied_str.encoding).to eq(Encoding::UTF_8)
      expect(copied_str.valid_encoding?).to be(true)
    end
  end
end
