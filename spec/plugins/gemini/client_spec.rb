require "spec_helper"
require_relative "../../../plugins/gemini/client"
require "norn/tool"

RSpec.describe Norn::Plugins::Gemini::Client do
  let(:api_key) { "test-gemini-key" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_gemini_client) { double("Gemini") }

  before do
    allow(::Gemini).to receive(:new).with(
      credentials: {
        service: "generative-language-api",
        api_key: api_key,
        version: "v1beta"
      },
      options: {
        model: "gemini-3.5-flash"
      }
    ).and_return(mock_gemini_client)
  end

  describe "#call" do
    it "returns a failure if API key is nil or empty" do
      bad_client = described_class.new(api_key: nil)
      result = bad_client.call([])
      expect(result).to be_failure
      expect(result.failure.message).to include("GEMINI_API_KEY environment variable is not set")
    end

    it "formats messages, includes sandbox instructions, calls Gemini API, and extracts content" do
      messages = [
        { role: :system, content: Norn.config.sandbox_info },
        { role: :user, content: "hi" },
        { role: :assistant, content: "hello" },
        { role: :user, content: "what is my name?" }
      ]

      expected_api_contents = [
        { role: "user", parts: [{ text: "hi" }] },
        { role: "model", parts: [{ text: "hello" }] },
        { role: "user", parts: [{ text: "what is my name?" }] }
      ]

      expected_system_instruction = {
        role: "user",
        parts: [{ text: Norn.config.sandbox_info }]
      }

      mock_api_response = [
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Your name is " }
                ]
              }
            }
          ]
        },
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Purple." }
                ]
              }
            }
          ]
        }
      ]

      expect(mock_gemini_client).to receive(:stream_generate_content).with(
        {
          contents: expected_api_contents,
          system_instruction: expected_system_instruction
        },
        server_sent_events: false
      ).and_return(mock_api_response)

      result = client.call(messages)
      expect(result).to be_success
      expect(result.value!).to eq({
        type: :text,
        content: "Your name is Purple.",
        parts: [{ "text" => "Your name is " }, { "text" => "Purple." }]
      })
    end

    it "translates Norn::Tool parameters to Google format with uppercase types and parses functionCalls in the response" do
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
          function_declarations: [
            {
              name: "file_read",
              description: "Read file",
              parameters: {
                type: "OBJECT",
                properties: { path: { type: "STRING" } },
                required: ["path"]
              }
            }
          ]
        }
      ]

      mock_api_response = [
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  {
                    "functionCall" => {
                      "name" => "file_read",
                      "args" => { "path" => "lib/norn.rb" }
                    }
                  }
                ]
              }
            }
          ]
        }
      ]

      expect(mock_gemini_client).to receive(:stream_generate_content).with(
        {
          contents: [{ role: "user", parts: [{ text: "read file" }] }],
          tools: expected_tools_schema
        },
        server_sent_events: false
      ).and_return(mock_api_response)

      result = client.call([{ role: :user, content: "read file" }], tools: [tool])
      expect(result).to be_success
      expect(result.value!).to eq({
        type: :tool_call,
        calls: [
          {
            id: nil,
            name: "file_read",
            arguments: { "path" => "lib/norn.rb" }
          }
        ],
        parts: [
          {
            "functionCall" => {
              "name" => "file_read",
              "args" => { "path" => "lib/norn.rb" }
            }
          }
        ]
      })
    end

    it "handles errors from the API gracefully by returning a failure" do
      messages = [{ role: :user, content: "hi" }]
      expect(mock_gemini_client).to receive(:stream_generate_content).and_raise(StandardError.new("Quota exceeded"))

      result = client.call(messages)
      expect(result).to be_failure
      expect(result.failure.message).to include("Quota exceeded")
    end
  end
end
