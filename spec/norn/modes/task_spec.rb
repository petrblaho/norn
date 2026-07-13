require "spec_helper"
require "norn/modes/task"
require "stringio"
require "dry/monads"

RSpec.describe Norn::Modes::Task do
  include Dry::Monads[:result]

  describe "#start" do
    it "returns failure if no prompt is given" do
      io = norn_io
      task_mode = described_class.new(output: io.output)
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

      # Stub sequential LLM calls
      stub_llm_responses([
        {
          type: :tool_call,
          calls: [
            {
              id: "call_123",
              name: "test_tool",
              arguments: { val: "my-val" }
            }
          ]
        },
        {
          type: :text,
          content: "I have successfully run the tool and completed the task!"
        }
      ], provider: "mock_provider")

      # Mock rendering hook
      rendered_called = false
      Norn::PluginManager.subscribe(:on_render_response) do |payload|
        payload[:text] = "RENDERED: #{payload[:text]}"
        rendered_called = true
        payload
      end

      io = norn_io
      task_mode = described_class.new(output: io.output)
      result = task_mode.start("Use the test tool with my-val")

      expect(result).to be_success

      expect(io).to have_produced_in_order(
        "Norn Autonomous Task Agent initialized.",
        "Running test_tool with arguments:",
        "my-val",
        "RENDERED: I have successfully run the tool and completed the task!"
      )
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

      # Stub sequential LLM calls
      stub_llm_responses([
        {
          type: :tool_call,
          calls: [
            {
              id: "call_999",
              name: "missing_tool",
              arguments: {}
            }
          ]
        },
        {
          type: :text,
          content: "Tool missing error handled."
        }
      ], provider: "mock_provider")

      io = norn_io
      task_mode = described_class.new(output: io.output)
      result = task_mode.start("Call missing tool")

      expect(result).to be_success
      expect(io).to have_produced("Running missing_tool")
      expect(task_mode.messages).to include(
        hash_including(role: "tool", content: "Error: Tool 'missing_tool' not found in registry.")
      )
    end
  end
end
