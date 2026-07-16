# Design Spec: Subprocess Execution - Phase 3: The Agent Bridge (Standardized A2A Communication)

* **Date**: 2026-07-15
* **Status**: Approved / Brainstormed
* **Authors**: Petr Blaho & Norn AI
* **Target Card**: [Subprocess Execution - Phase 3: The Agent Bridge (Standardized A2A Communication)](https://app.basecamp.com/5717936/buckets/48052540/card_tables/cards/10097083804)

---

## 1. Context & Business Case

With Phase 2 successfully implementing state-preserving, persistent subshell execution and real-time output event hooks, Norn is fully equipped with the local execution capabilities needed by advanced agents. 

Phase 3 introduces the **Agent Bridge**, which exposes Norn's tools and execution state to external parent or coordinator agents. To support a distributed multi-agent swarm where specialized agents connect and orchestrate each other over networks, this bridge conforms to the open-source **A2A (Agent-to-Agent) Project** protocol standard.

To maintain Norn's core design principles—minimal dependency bloat, high execution speed, and decoupled pluggability—this bridge is implemented with an **Abstract Network Transport Layer**. This decouples message parsing and execution routing from the network connection protocols, allowing zero-dependency local TCP routing today and drop-in WebSocket support tomorrow.

---

## 2. Architectural Design & Component Boundaries

We decompose our Agent Bridge into three decoupled components within the newly introduced `a2a` plugin namespace:

```
                            ┌────────────────────────────────────┐
                            │        External Parent Agent       │
                            └─────────────────┬──────────────────┘
                                              │ (JSON-RPC over Network)
                                              ▼
                            ┌────────────────────────────────────┐
                            │    Norn::Plugins::A2A::Transport   │ (TCP / Future WS)
                            └─────────────────┬──────────────────┘
                                              │ (Yields raw lines)
                                              ▼
                            ┌────────────────────────────────────┐
                            │     Norn::Plugins::A2A::Server     │ (Message Broker)
                            └─────────┬────────────────┬─────────┘
                                      │                │
                        (Executes Tools)               │ (Intercepts :on_subprocess_output)
                                      ▼                ▼
                            ┌──────────────────┐  ┌──────────────────┐
                            │   ToolRegistry   │  │  PluginManager   │
                            └──────────────────┘  └──────────────────┘
```

### 2.1 Component: `Norn::Plugins::A2A::Transport::Base`
* **File**: `plugins/a2a/transport/base.rb`
* **Responsibilities**:
  * Define the abstract transport interface contract.
  * Define `#start`, `#stop`, and `#write(payload)` interfaces.
  * Yield incoming string lines to a registered block.

### 2.2 Component: `Norn::Plugins::A2A::Transport::TCP`
* **File**: `plugins/a2a/transport/tcp.rb`
* **Responsibilities**:
  * Inherit from `Base`.
  * Open a `TCPServer` bound to a configurable port (default: `4567`) on a background thread.
  * Accept socket connections, handle incoming buffered packets safely, split on newline boundaries (`\n`), and yield complete raw request strings to the callback block.
  * Provide concurrent-safe writing of payload lines back to the active socket.

### 2.3 Component: `Norn::Plugins::A2A::Server`
* **File**: `plugins/a2a/server.rb`
* **Responsibilities**:
  * Act as the central JSON-RPC 2.0 broker.
  * Consume incoming request strings, validate JSON-RPC envelopes, and parse methods.
  * Route `agent.getCapabilities` to Norn's session state and return metadata.
  * Route `agent.listTools` to `Norn::ToolRegistry` to serialize and return active tool schemas.
  * Route `agent.executeTool` to execute target tools via `Tool#call`.
  * Intercept Norn's `:on_subprocess_output` hook and stream raw character chunks back to the client as real-time `agent.onProgress` JSON-RPC notifications.

---

## 3. JSON-RPC 2.0 Message Protocol Schema Mappings

All message payloads follow the standard JSON-RPC 2.0 specification.

### 3.1 Handshake & Tool Discovery (`agent.listTools`)
* **Request**:
  ```json
  { "jsonrpc": "2.0", "method": "agent.listTools", "id": "req_1" }
  ```
* **Response**:
  ```json
  {
    "jsonrpc": "2.0",
    "result": {
      "tools": [
        {
          "name": "execute_command",
          "description": "Executes raw shell or command-line instructions safely in the project workspace root.",
          "schema": {
            "type": "object",
            "properties": {
              "command": { "type": "string", "description": "The raw shell command string..." }
            },
            "required": ["command"]
          }
        }
      ]
    },
    "id": "req_1"
  }
  ```

### 3.2 Capability Inspection (`agent.getCapabilities`)
* **Request**:
  ```json
  { "jsonrpc": "2.0", "method": "agent.getCapabilities", "id": "req_2" }
  ```
* **Response**:
  ```json
  {
    "jsonrpc": "2.0",
    "result": {
      "agent": {
        "name": "norn",
        "version": "1.0.0"
      },
      "capabilities": ["sys_execute", "file_read", "file_write"]
    },
    "id": "req_2"
  }
  ```

### 3.3 Tool Execution & Real-Time Hook Streaming (`agent.executeTool` & `agent.onProgress`)
1. **Client Dispatches Task**:
   ```json
   {
     "jsonrpc": "2.0",
     "method": "agent.executeTool",
     "params": {
       "name": "execute_command",
       "arguments": { "command": "echo 'hello swarm'" }
     },
     "id": "req_3"
   }
   ```
2. **Real-Time Stream Notification Intercepts**:
   As the subshell execution prints chunks, the server captures `:on_subprocess_output` and streams:
   ```json
   {
     "jsonrpc": "2.0",
     "method": "agent.onProgress",
     "params": {
       "stream": "stdout",
       "chunk": "hello swarm\n"
     }
   }
   ```
3. **Execution Completes & Final Response Returned**:
   ```json
   {
     "jsonrpc": "2.0",
     "result": {
       "stdout": "hello swarm\n",
       "stderr": "",
       "exit_code": 0
     },
     "id": "req_3"
   }
   ```

---

## 4. Hook Streaming Integration Details

To wire stream intercepts during tool runs, the `A2A::Server` subscribes dynamically to `:on_subprocess_output` inside Norn's `PluginManager`. 

```ruby
# Dynamic subscription mapping
Norn::PluginManager.subscribe(:on_subprocess_output) do |payload|
  if @active_execution_id
    notification = {
      jsonrpc: "2.0",
      method: "agent.onProgress",
      params: {
        stream: payload[:stream].to_s,
        chunk: payload[:chunk]
      }
    }
    @active_transport.write(JSON.generate(notification) + "\n")
  end
end
```

To prevent race conditions, the server maintains an `@active_execution_id` variable. Progress events are only forwarded if they correlate to an active, in-flight client RPC execution context.

---

## 5. Security & Isolation Boundaries

1. **Gatekeeper Enforcement**: Executing tools via `agent.executeTool` runs through the standard Norn tool invocation engine. All capability checks, static validator filters (e.g. blocking `rm -rf /`), and user interaction prompts remain completely active.
2. **Local Port Binding Safety**: By default, the TCP server binds strictly to `127.0.0.1` (`localhost`), ensuring external network addresses cannot execute arbitrary commands unless explicitly configured by the user.

---

## 6. Testing Strategy

We will write robust, speed-optimized specs under `spec/plugins/a2a/` utilizing isolated local loopback sockets to guarantee 100% test isolation:

1. **Protocol Serialization Tests**: Verify correct mapping of `Norn::Tool` schemas to JSON-RPC parameter objects.
2. **Loopback Handshake Tests**: Spawn the A2A Server on an ephemeral local port, connect a test `TCPSocket` client, send raw request lines, and assert correct response serialization.
3. **Stream Intercept Tests**: Trigger `execute_command` through an A2A request, and verify that progress notifications are emitted over the loopback client socket before the final outcome response.
4. **Port Allocation Safety**: Ensure ports used in tests are automatically closed on test teardown to prevent socket leakage.
