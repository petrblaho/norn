require "spec_helper"
require_relative "../../../plugins/openai/client"
require "norn/tool"

RSpec.describe Norn::Plugins::OpenAI::Client do
  let(:api_key) { "test-api-key" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_openai_client) { double("OpenAI::Client") }
  let(:mock_responses_resource) { double("OpenAI::Resources::Responses") }

  before do
    allow(::OpenAI::Client).to receive(:new).with(api_key: api_key).and_return(mock_openai_client)
    allow(mock_openai_client).to receive(:responses).and_return(mock_responses_resource)
  end

  describe "#call" do
    it "returns a failure if API key is nil or empty" do
      bad_client = described_class.new(api_key: nil)
      result = bad_client.call([])
      expect(result).to be_failure
      expect(result.failure.message).to include("OPENAI_API_KEY environment variable is not set")
    end

    it "formats messages, includes sandbox info, calls OpenAI API, and returns content" do
      messages = [
        { role: :system, content: Norn.config.sandbox_info },
        { role: :user, content: "hello" }
      ]

      expected_api_messages = [
        { role: :system, content: Norn.config.sandbox_info },
        { role: :user, content: "hello" }
      ]

      mock_response = double("Response", output_text: "Hello human!")

      expect(mock_responses_resource).to receive(:create).with(
        model: "gpt-4o-mini",
        temperature: 0.7,
        input: expected_api_messages
      ).and_return(mock_response)

      result = client.call(messages)
      expect(result).to be_success
      expect(result.value!).to eq({ type: :text, content: "Hello human!" })
    end

    it "translates Norn::Tool parameters to OpenAI format and parses tool calls in the response" do
      tool = Norn::Tool.new(
        "file_read",
        "Read file",
        {
          type: "object",
          properties: { path: { type: "string" } },
          required: ["path"]
        }
      ) { "dummy" }

      expected_tools_schema = [
        {
          type: "function",
          function: {
            name: "file_read",
            description: "Read file",
            parameters: {
              type: "object",
              properties: { path: { type: "string" } },
              required: ["path"]
            }
          }
        }
      ]

      # Mock an item in the response output
      mock_tool_call_item = double("ResponseFunctionToolCall",
        type: :function_call,
        call_id: "call_abc",
        name: "file_read",
        arguments: '{"path":"lib/norn.rb"}'
      )

      mock_response = double("Response",
        output: [mock_tool_call_item]
      )

      expect(mock_responses_resource).to receive(:create).with(
        model: "gpt-4o-mini",
        temperature: 0.7,
        input: [{ role: :user, content: "read file" }],
        tools: expected_tools_schema
      ).and_return(mock_response)

      result = client.call([{ role: :user, content: "read file" }], tools: [tool])
      expect(result).to be_success
      expect(result.value!).to eq({
        type: :tool_call,
        calls: [
          {
            id: "call_abc",
            name: "file_read",
            arguments: { "path" => "lib/norn.rb" }
          }
        ]
      })
    end

    it "handles API error messages properly by returning a failure" do
      messages = [{ role: :user, content: "hello" }]

      expect(mock_responses_resource).to receive(:create).and_raise(StandardError.new("Rate limit reached"))

      result = client.call(messages)
      expect(result).to be_failure
      expect(result.failure.message).to include("Rate limit reached")
    end
  end
end
