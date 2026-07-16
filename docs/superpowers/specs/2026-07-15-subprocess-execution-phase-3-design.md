# Design Spec: Subprocess Execution - Phase 3: The Agent Bridge (Standardized A2A Communication)

* **Date**: 2026-07-15
* **Status**: Approved / Brainstormed
* **Authors**: Petr Blaho & Norn AI
* **Target Card**: [Subprocess Execution - Phase 3: The Agent Bridge (Standardized A2A Communication)](https://app.basecamp.com/5717936/buckets/48052540/card_tables/cards/10097083804)
* **Protocol Target**: [A2A v1.0 Specification (Agent2Agent Protocol)](https://a2a-protocol.org/latest/specification/)

---

## 1. Context & Business Case

With Phase 2 successfully implementing state-preserving, persistent subshell execution and real-time output event hooks, Norn is fully equipped with the local execution capabilities needed by advanced agents.

Phase 3 introduces the **Agent Bridge**, which exposes Norn's tools and execution state to external parent or coordinator agents. To support a distributed multi-agent swarm where specialized agents connect and orchestrate each other over networks, this bridge strictly conforms to the Linux Foundation open-source **Agent2Agent (A2A) Protocol v1.0 standard**.

To maintain Norn's core design principles—minimal dependency bloat, high execution speed, and decoupled pluggability—this bridge is implemented with an **Abstract Network Transport Layer**. This decouples message parsing and execution routing from the network connection protocols, allowing zero-dependency local TCP routing today and drop-in WebSocket/HTTP support tomorrow.

---

## 2. Architectural Design & Component Boundaries

We decompose our Agent Bridge into three decoupled components within the newly introduced `a2a` plugin namespace:

```
                            ┌────────────────────────────────────┐
                            │        External Parent Agent       │
                            └─────────────────┬──────────────────┘
                                              │ (JSON-RPC 2.0 over Network)
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
  * Act as the central JSON-RPC 2.0 broker mapping to A2A Core Operations.
  * Consume incoming request strings, validate JSON-RPC envelopes, and parse methods.
  * Route `agent.getExtendedAgentCard` to return the A2A `AgentCard` structure detailing Norn's metadata, provider, active capabilities, and available skills.
  * Route `agent.sendMessage` to trigger target tools via `Tool#call` synchronously.
  * Route `agent.sendStreamingMessage` to trigger target tools and stream progress updates.
  * Intercept Norn's `:on_subprocess_output` hook and stream raw character chunks back to the client as real-time `agent.onProgress` JSON-RPC notifications.

---

## 3. JSON-RPC 2.0 Message Protocol Schema Mappings (A2A v1.0 Compliant)

All message payloads follow the official A2A v1.0 JSON-RPC protocol bindings.

### 3.1 Handshake & Capability Discovery (`agent.getExtendedAgentCard`)
* **Request**:
  ```json
  { "jsonrpc": "2.0", "method": "agent.getExtendedAgentCard", "id": "req_1" }
  ```
* **Response**:
  Returns the serialized A2A `AgentCard` describing Norn:
  ```json
  {
    "jsonrpc": "2.0",
    "result": {
      "name": "norn",
      "version": "1.0.0",
      "capabilities": {
        "streaming": true,
        "push_notifications": false,
        "extended_agent_card": true
      },
      "skills": [
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

### 3.2 Synchronous Tool Execution (`agent.sendMessage`)
* **Request**:
  Executes a command block on the agent synchronously. Parameters follow A2A `SendMessageRequest` structure:
  ```json
  {
    "jsonrpc": "2.0",
    "method": "agent.sendMessage",
    "params": {
      "message": {
        "role": "user",
        "parts": [
          { "text": "execute_command command='pwd'" }
        ]
      },
      "configuration": {
        "return_immediately": false
      }
    },
    "id": "req_2"
  }
  ```
* **Response**:
  Returns the final A2A `Task` status and final text response:
  ```json
  {
    "jsonrpc": "2.0",
    "result": {
      "id": "task_abc123",
      "status": {
        "state": "COMPLETED"
      },
      "parts": [
        { "text": "/home/user/workspace/norn\n" }
      ]
    },
    "id": "req_2"
  }
  ```

### 3.3 Streaming Tool Execution (`agent.sendStreamingMessage` & Progress Stream Notifications)
1. **Client Dispatches Task with Streaming**:
   ```json
   {
     "jsonrpc": "2.0",
     "method": "agent.sendStreamingMessage",
     "params": {
       "message": {
         "role": "user",
         "parts": [
           { "text": "execute_command command=\"echo 'hello swarm'\"" }
         ]
       }
     },
     "id": "req_3"
   }
   ```
2. **Real-Time Progress Event Delivery**:
   As the subshell execution prints chunks, the server captures `:on_subprocess_output` and streams JSON-RPC notification lines back to the active client:
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
3. **Task Completion Response**:
   Once the stream is complete, Norn returns the final task status object:
   ```json
   {
     "jsonrpc": "2.0",
     "result": {
       "id": "task_req_3",
       "status": {
         "state": "COMPLETED"
       }
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

1. **Gatekeeper Enforcement**: Executing tools via `agent.sendMessage` runs through the standard Norn tool invocation engine. All capability checks, static validator filters (e.g. blocking `rm -rf /`), and user interaction prompts remain completely active.
2. **Local Port Binding Safety**: By default, the TCP server binds strictly to `127.0.0.1` (`localhost`), ensuring external network addresses cannot execute arbitrary commands unless explicitly configured by the user.

---

## 6. Testing Strategy

We will write robust, speed-optimized specs under `spec/plugins/a2a/` utilizing isolated local loopback sockets to guarantee 100% test isolation:

1. **Protocol Serialization Tests**: Verify correct mapping of `Norn::Tool` schemas to standard A2A `AgentCard` and `SendMessageRequest` schemas.
2. **Loopback Handshake Tests**: Spawn the A2A Server on an ephemeral local port, connect a test `TCPSocket` client, send raw request lines, and assert correct response serialization.
3. **Stream Intercept Tests**: Trigger `execute_command` through an `agent.sendStreamingMessage` request, and verify that progress notifications are emitted over the loopback client socket before the final task completion response.
4. **Port Allocation Safety**: Ensure ports used in tests are automatically closed on test teardown to prevent socket leakage.
