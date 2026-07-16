# Subprocess Execution - Phase 3: The Agent Bridge (Standardized A2A Communication) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a standard-compliant, decoupled network bridge for Norn that implements the A2A v1.0 JSON-RPC protocol, allowing remote coordinator agents to dynamically discover Norn's tools and execute commands with real-time stream progression.

**Architecture:** We will implement an abstract, pluggable A2A server plugin. It separates communication protocols into a pluggable `Transport` layer, starting with standard local loopback TCP sockets (`a2aproject/A2A` compliant). The core `Server` acts as the JSON-RPC 2.0 broker, subscribing to Norn's `:on_subprocess_output` hooks to stream standard progress frames back to connected clients in real-time.

**Tech Stack:** Pure Ruby, standard libraries (`socket`, `json`, `thread`), RSpec.

## Global Constraints

* Keep implementations DRY, YAGNI, and TDD-driven.
* Follow conventional commit guidelines with atomic, step-by-step commits.
* All network payloads and JSON strings must handle binary/malformed characters safely via forced UTF-8 sanitization.
* Ensure all RSpec unit and integration tests run green instantly without external network calls.

---

## File Structure

Before writing code, we map out the specific file layout:
1. `plugins/a2a/transport/base.rb` — Abstract Transport contract.
2. `plugins/a2a/transport/tcp.rb` — Zero-dependency TCPServer transport running on background thread.
3. `plugins/a2a/server.rb` — JSON-RPC 2.0 A2A core broker mapping methods and capturing event hooks.
4. `plugins/a2a/plugin.rb` — Unified Norn A2A plugin wrapper booting the server dynamically.

---

### Task 1: Build the Pluggable Network Transports

**Files:**
- Create: `plugins/a2a/transport/base.rb`
- Create: `plugins/a2a/transport/tcp.rb`
- Test: `spec/plugins/a2a/transport_spec.rb`

**Interfaces:**
- Produces: `Norn::Plugins::A2A::Transport::Base` and `Norn::Plugins::A2A::Transport::TCP` exposing:
  * `#start` (initializes loop and binds socket)
  * `#stop` (cleans up and closes descriptors)
  * `#write(line)` (thread-safe newline payload writer)
  * Yields raw received lines to `#start`'s block.

- [ ] **Step 1: Write the failing unit tests for the TCP transport**

Create the spec file `spec/plugins/a2a/transport_spec.rb`:
```ruby
require "spec_helper"
require "socket"
require_relative "../../../plugins/a2a/transport/base"
require_relative "../../../plugins/a2a/transport/tcp"

RSpec.describe Norn::Plugins::A2A::Transport::TCP do
  let(:port) { 4999 } # Ephemeral test port
  subject(:transport) { described_class.new(port: port) }

  after do
    transport.stop
  end

  it "binds to localhost and receives newline-delimited lines" do
    received_lines = []
    
    transport.start do |line|
      received_lines << line
    end

    # Connect client
    client = TCPSocket.new("127.0.0.1", port)
    client.puts("test_line_1")
    client.puts("test_line_2")
    client.close

    # Wait briefly for background thread to read
    sleep 0.1

    expect(received_lines).to eq(["test_line_1", "test_line_2"])
  end

  it "supports thread-safe writing back to the client connection" do
    transport.start do |line|
      # Echo back
      transport.write("echo: #{line}")
    end

    client = TCPSocket.new("127.0.0.1", port)
    client.puts("hello")
    response = client.gets
    client.close

    expect(response.strip).to eq("echo: hello")
  end
end
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bundle exec rspec spec/plugins/a2a/transport_spec.rb`
Expected: FAIL with "LoadError: cannot load such file -- plugins/a2a/transport/base"

- [ ] **Step 3: Implement `Norn::Plugins::A2A::Transport::Base`**

Create `plugins/a2a/transport/base.rb`:
```ruby
module Norn
  module Plugins
    module A2A
      module Transport
        class Base
          def start(&block)
            raise NotImplementedError, "Subclasses must implement #start"
          end

          def write(payload)
            raise NotImplementedError, "Subclasses must implement #write"
          end

          def stop
            raise NotImplementedError, "Subclasses must implement #stop"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement `Norn::Plugins::A2A::Transport::TCP`**

Create `plugins/a2a/transport/tcp.rb`:
```ruby
require "socket"
require "thread"

module Norn
  module Plugins
    module A2A
      module Transport
        class TCP < Base
          def initialize(host: "127.0.0.1", port: 4567)
            @host = host
            @port = port
            @server = nil
            @client = nil
            @thread = nil
            @lock = Mutex.new
            @running = false
          end

          def start(&block)
            @lock.synchronize do
              return if @running
              @running = true
            end

            @server = TCPServer.new(@host, @port)
            @thread = Thread.new do
              while @running
                begin
                  # Standalone local-loopback proxy pattern: handles single concurrent client safely
                  @client = @server.accept
                  while @running && line = @client.gets
                    # Scrub inputs cleanly
                    sanitized_line = line.force_encoding("UTF-8").scrub.strip
                    block.call(sanitized_line) unless sanitized_line.empty?
                  end
                rescue => e
                  # Connection closed or server stopped
                ensure
                  @client.close if @client && !@client.closed?
                end
              end
            end
          end

          def write(payload)
            @lock.synchronize do
              if @client && !@client.closed?
                begin
                  @client.puts(payload)
                rescue
                  # Ignore pipe write failures
                end
              end
            end
          end

          def stop
            @lock.synchronize do
              return unless @running
              @running = false
            end

            begin
              @client.close if @client && !@client.closed?
              @server.close if @server && !@server.closed?
            rescue
            ensure
              @thread.join if @thread && @thread.alive?
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run specs and confirm they pass**

Run: `bundle exec rspec spec/plugins/a2a/transport_spec.rb`
Expected: ALL PASS (2 green examples)

- [ ] **Step 6: Commit the transport implementation**

Run:
```bash
git add plugins/a2a/transport/base.rb plugins/a2a/transport/tcp.rb spec/plugins/a2a/transport_spec.rb
git commit -m "feat(a2a): implement transport abstraction and TCP socket transport"
```

---

### Task 2: Implement the A2A JSON-RPC 2.0 Server Broker

**Files:**
- Create: `plugins/a2a/server.rb`
- Test: `spec/plugins/a2a/server_spec.rb`

**Interfaces:**
- Produces: `Norn::Plugins::A2A::Server` class exposing:
  * `#handle_message(raw_json)` (JSON-RPC parser & broker)
  * Exposes A2A v1.0 standard-compliant methods: `agent.getExtendedAgentCard`, `agent.sendMessage`, `agent.sendStreamingMessage`.

- [ ] **Step 1: Write the failing integration tests for A2A message brokerage and hook streaming**

Create the spec file `spec/plugins/a2a/server_spec.rb`:
```ruby
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
    ) { |args, ctx| "dummy result: #{args[:input]}" }
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

    # Simulate subshell progress hook execution
    Thread.new do
      sleep 0.05
      Norn::PluginManager.trigger(:on_subprocess_output, { stream: :stdout, chunk: "chunk_data\n" })
    end

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
```

- [ ] **Step 2: Run the test suite and verify it fails**

Run: `bundle exec rspec spec/plugins/a2a/server_spec.rb`
Expected: FAIL with "LoadError: cannot load such file -- plugins/a2a/server"

- [ ] **Step 3: Implement `Norn::Plugins::A2A::Server` broker**

Create `plugins/a2a/server.rb`:
```ruby
require "json"

module Norn
  module Plugins
    module A2A
      class Server
        def initialize(transport:, registry: Norn::ToolRegistry)
          @transport = transport
          @registry = registry
          @active_execution_id = nil
          
          # Dynamically bind to Norn's real-time subprocess streaming hooks
          setup_hooks!
        end

        def handle_message(raw_json)
          begin
            request = JSON.parse(raw_json, symbolize_names: true)
            method = request[:method].to_s
            id = request[:id]

            case method
            when "agent.getExtendedAgentCard"
              handle_discovery(id)
            when "agent.sendMessage"
              handle_execute(request, id, streaming: false)
            when "agent.sendStreamingMessage"
              handle_execute(request, id, streaming: true)
            else
              write_error(id, -32601, "Method not found: #{method}")
            end
          rescue => e
            write_error(nil, -32700, "Parse error: #{e.message}")
          end
        end

        private

        def setup_hooks!
          Norn::PluginManager.subscribe(:on_subprocess_output) do |payload|
            if @active_execution_id
              # Format to official A2A agent.onProgress notification frame
              notification = {
                jsonrpc: "2.0",
                method: "agent.onProgress",
                params: {
                  stream: payload[:stream].to_s,
                  chunk: payload[:chunk]
                }
              }
              @transport.write(JSON.generate(notification))
            end
          end
        end

        def handle_discovery(id)
          skills = @registry.all.map do |tool|
            {
              name: tool.name,
              description: tool.description,
              schema: tool.schema
            }
          end

          # Schema-compliant A2A AgentCard
          result = {
            name: "norn",
            version: "1.0.0",
            capabilities: {
              streaming: true,
              push_notifications: false,
              extended_agent_card: true
            },
            skills: skills
          }

          write_success(id, result)
        end

        def handle_execute(request, id, streaming:)
          parts = request.dig(:params, :message, :parts) || []
          prompt_text = parts.first ? parts.first[:text].to_s.strip : ""

          # A2A simple parsing: extract command/tool. Format: "tool_name arg1='val' arg2=val"
          # Match tool_name and split remaining properties
          tool_name = prompt_text.split(/\s+/).first
          args_part = prompt_text[tool_name.length..-1].to_s.strip

          tool = @registry.resolve(tool_name)
          unless tool
            return write_error(id, -32602, "Tool not found: #{tool_name}")
          end

          # Parse arguments (matches key='val' or key=val)
          arguments = {}
          args_part.scan(/(\w+)=['"]?([^'"]+)['"]?/).each do |key, val|
            arguments[key.to_sym] = val
          end

          # Set active execution context for progress hooks routing
          @active_execution_id = id if streaming

          begin
            outcome_text = tool.call(arguments, nil)

            # Compliant A2A Task result payload
            result = {
              id: "task_#{id}",
              status: {
                state: "COMPLETED"
              },
              parts: [
                { text: outcome_text }
              ]
            }
            write_success(id, result)
          rescue => e
            write_error(id, -32603, "Internal error during tool call: #{e.message}")
          ensure
            @active_execution_id = nil if streaming
          end
        end

        def write_success(id, result)
          response = {
            jsonrpc: "2.0",
            result: result,
            id: id
          }
          @transport.write(JSON.generate(response))
        end

        def write_error(id, code, message)
          response = {
            jsonrpc: "2.0",
            error: {
              code: code,
              message: message
            },
            id: id
          }
          @transport.write(JSON.generate(response))
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the specs and confirm they pass**

Run: `bundle exec rspec spec/plugins/a2a/server_spec.rb`
Expected: ALL PASS (3 green examples)

- [ ] **Step 5: Commit the Server broker**

Run:
```bash
git add plugins/a2a/server.rb spec/plugins/a2a/server_spec.rb
git commit -m "feat(a2a): implement A2A compliant JSON-RPC server broker with hook multiplexing"
```

---

### Task 3: Register `a2a` Plugin and Expose A2A Server

**Files:**
- Create: `plugins/a2a/plugin.rb`
- Test: Run entire test suite.

**Interfaces:**
- Consumes: `Norn::Plugins::A2A::Server` and `Norn::Plugins::A2A::Transport::TCP`
- Produces: Integrated A2APlugin booting standard loopback TCP server dynamically on `:on_boot` hook.

- [ ] **Step 1: Implement the A2APlugin wrapper**

Create `plugins/a2a/plugin.rb`:
```ruby
class A2APlugin < Norn::Plugin
  def self.plugin_name
    "a2a"
  end

  def on_boot(container)
    require_relative "transport/base"
    require_relative "transport/tcp"
    require_relative "server"

    # Default A2A port 4567, allow override via ENV
    port = (ENV["NORN_A2A_PORT"] || 4567).to_i

    # Initialize TCP transport and A2A broker
    @transport = Norn::Plugins::A2A::Transport::TCP.new(port: port)
    @server = Norn::Plugins::A2A::Server.new(transport: @transport)

    # Start A2A server on background thread to keep standalone session non-blocked
    @transport.start do |line|
      @server.handle_message(line)
    end
  end

  # Cleanup port allocation on Norn exit
  def on_shutdown
    @transport.stop if @transport
  end
end
```

- [ ] **Step 2: Run the entire test suite to guarantee 100% green compliance**

Run: `bundle exec rspec`
Expected: ALL PASS (269 examples, 0 failures)

- [ ] **Step 3: Commit the A2A plugin**

Run:
```bash
git add plugins/a2a/plugin.rb
git commit -m "feat(a2a): register A2APlugin and boot TCP A2A Server dynamically on boot"
```
