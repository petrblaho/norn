require "spec_helper"
require "json"
require "norn/plugin_manager"
require "norn/tool_registry"
require_relative "../../../plugins/a2a/transport/base"
require_relative "../../../plugins/a2a/server"

RSpec.describe Norn::Plugins::A2A::Server do
  # Mock transport double
  class MockTransport < Norn::Plugins::A2A::Transport::Base
    attr_reader :written_payloads
    def initialize; @written_payloads = []; end
    def write(payload); @written_payloads << payload.strip; end
    def start; end
    def stop; end
  end

  let(:transport) { MockTransport.new }
  let(:registry) { Norn::ToolRegistry }
  subject(:server) { described_class.new(transport: transport, registry: registry) }

  before do
    Norn::PluginManager.reset!
    Norn::PluginManager.register_core_hooks!
    Norn::ToolRegistry.clear!

    # Register a standard dummy tool for testing
    dummy_tool = Norn::Tool.new(
      "dummy", "Dummy description",
      { type: "object", properties: { input: { type: "string" } } }
    ) do |args, ctx|
      # Trigger output hook synchronously inside execution block
      Norn::PluginManager.trigger(:on_subprocess_output, { stream: :stdout, chunk: "chunk_data\n" })
      "dummy result: #{args[:input]}"
    end
    registry.register(dummy_tool)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  it "handles agent.getExtendedAgentCard and returns compliant AgentCard" do
    request = {
      jsonrpc: "2.0",
      method: "agent.getExtendedAgentCard",
      id: "disc_1"
    }

    server.handle_message(JSON.generate(request))
    expect(transport.written_payloads.length).to eq(1)

    response = JSON.parse(transport.written_payloads.first)
    expect(response["id"]).to eq("disc_1")
    expect(response["result"]["name"]).to eq("norn")
    expect(response["result"]["capabilities"]["streaming"]).to be true
    expect(response["result"]["skills"].any? { |s| s["name"] == "dummy" }).to be true
  end

  it "handles agent.sendMessage synchronously and returns final task block" do
    request = {
      jsonrpc: "2.0",
      method: "agent.sendMessage",
      params: {
        message: {
          role: "user",
          parts: [{ text: "dummy input='test'" }]
        }
      },
      id: "msg_2"
    }

    server.handle_message(JSON.generate(request))
    expect(transport.written_payloads.length).to eq(1)

    response = JSON.parse(transport.written_payloads.first)
    expect(response["id"]).to eq("msg_2")
    expect(response["result"]["status"]["state"]).to eq("COMPLETED")
    expect(response["result"]["parts"].first["text"]).to include("dummy result: test")
  end

  it "handles agent.sendStreamingMessage and intercepts progress hooks" do
    request = {
      jsonrpc: "2.0",
      method: "agent.sendStreamingMessage",
      params: {
        message: {
          role: "user",
          parts: [{ text: "dummy input='progress'" }]
        }
      },
      id: "stream_3"
    }

    server.handle_message(JSON.generate(request))
    
    # Expect at least progress notification + final completed response
    expect(transport.written_payloads.length).to be >= 2
    
    # Verify progress notifications
    progress_event = transport.written_payloads.find { |p| p.include?("agent.onProgress") }
    expect(progress_event).not_to be_nil
    parsed_progress = JSON.parse(progress_event)
    expect(parsed_progress["params"]["chunk"]).to eq("chunk_data\n")
    
    # Verify final completed response
    final_event = transport.written_payloads.find { |p| p.include?("COMPLETED") }
    expect(final_event).not_to be_nil
  end
end
