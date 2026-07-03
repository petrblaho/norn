require "spec_helper"
require "norn/modes/task"
require "stringio"
require "dry/monads"

RSpec.describe Norn::Modes::Task do
  include Dry::Monads[:result]

  let(:output) { StringIO.new }
  let(:mock_client) { double("LLMClient", model: "mock-model") }

  before do
    allow(Norn::Container).to receive(:[]).and_call_original
    allow(Norn::Container).to receive(:[]).with("llm.mock_provider").and_return(mock_client)
    Norn.config.llm_provider = "mock_provider"
  end

  describe "#start" do
    it "returns failure if no prompt is given" do
      task_mode = described_class.new(output: output)
      expect(task_mode.start(nil)).to be_failure
      expect(task_mode.start("   ")).to be_failure
    end

    it "runs a ReAct loop: executes tool call, then terminates on text response" do
      # Let's clear the tools and register a mock tool
      Norn::ToolRegistry.clear!
      
      tool_executed = false
      mock_tool = Norn::Tool.new("test_tool", "A test tool", { type: "object" }, required_capabilities: [:sys_read]) do |args|
        tool_executed = true
        "Tool execution output: #{args[:val]}"
      end
      Norn::ToolRegistry.register(mock_tool)

      # 1st LLM call: returns a tool call wrapped in Success
      expect(mock_client).to receive(:call).with(
        an_instance_of(Array),
        tools: [mock_tool]
      ).and_return(Success({
        type: :tool_call,
        calls: [
          {
            id: "call_123",
            name: "test_tool",
            arguments: { val: "my-val" }
          }
        ]
      }))

      # 2nd LLM call: returns text response after receiving tool result wrapped in Success
      expect(mock_client).to receive(:call).with(
        an_instance_of(Array),
        tools: [mock_tool]
      ).and_return(Success({
        type: :text,
        content: "I have successfully run the tool and completed the task!"
      }))

      # Mock rendering hook
      rendered_called = false
      Norn::PluginManager.subscribe(:on_render_response) do |payload|
        payload[:text] = "RENDERED: #{payload[:text]}"
        rendered_called = true
        payload
      end

      task_mode = described_class.new(output: output)
      result = task_mode.start("Use the test tool with my-val")

      expect(result).to be_success

      output_str = output.string
      expect(output_str).to include("Norn Autonomous Task Agent initialized.")
      expect(output_str).to include("🔧 Running test_tool with arguments:")
      expect(output_str).to include("my-val")
      expect(output_str).to include("RENDERED: I have successfully run the tool and completed the task!")
      expect(tool_executed).to be(true)
      expect(rendered_called).to be(true)

      # Verify final messages structure
      expect(task_mode.messages).to eq([
        { role: "user", content: "Use the test tool with my-val" },
        {
          role: "assistant",
          content: nil,
          tool_calls: [
            { id: "call_123", name: "test_tool", arguments: { val: "my-val" } }
          ]
        },
        {
          role: "tool",
          tool_call_id: "call_123",
          name: "test_tool",
          content: "Tool execution output: my-val"
        },
        {
          role: "assistant",
          content: "I have successfully run the tool and completed the task!"
        }
      ])
    end

    it "handles missing or failing tools gracefully" do
      Norn::ToolRegistry.clear!

      # LLM calls a non-existent tool wrapped in Success
      expect(mock_client).to receive(:call).with(
        an_instance_of(Array)
      ).and_return(Success({
        type: :tool_call,
        calls: [
          {
            id: "call_999",
            name: "missing_tool",
            arguments: {}
          }
        ]
      }))

      # LLM responds after the failure wrapped in Success
      expect(mock_client).to receive(:call).with(
        an_instance_of(Array)
      ).and_return(Success({
        type: :text,
        content: "Tool missing error handled."
      }))

      task_mode = described_class.new(output: output)
      result = task_mode.start("Call missing tool")

      expect(result).to be_success
      expect(output.string).to include("🔧 Running missing_tool")
      expect(task_mode.messages).to include(
        hash_including(role: "tool", content: "Error: Tool 'missing_tool' not found in registry.")
      )
    end
  end
end
