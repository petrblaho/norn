# Ruby Terminal AI Agent Blueprint

A modern, dependency-stable architecture for building a terminal AI agent (alternative to Nod…

## Core Philosophy
Avoid native C-binding nightmares (Node-gyp, SQLite/LanceDB ABI mismatches) and NPM peer-depe…

## Stack Architecture

### 1. The CLI Router (`dry-cli`)
Handles argument parsing and command routing without enforcing UI opinions (unlike Thor).
```ruby
# Example: bin/agent task "refactor auth" --fast
class TaskCommand < Dry::CLI::Command
  argument :prompt, required: true
  option :fast, type: :boolean, default: false

  def call(prompt:, fast:)
    # dry-cli finishes here, hands off to the application
    Agent.new.run(prompt)
  end
end
```

### 2. Dependency Injection (`dry-system`)
Avoids global state. Registers tools, memory stores, and LLM clients. Makes the agent highly …

### 3. Tool Calling & Validation (`dry-struct`)
Enforces strict JSON schemas for LLM tool calling. If Claude wants to use the `bash` tool, `d…

### 4. Terminal UI (`tty-toolkit`)
Takes over once `dry-cli` routes the command.
*   **`tty-prompt`**: Interactive menus and confirmations (e.g., "Allow agent to run `rm -rf`…
*   **`tty-spinner`**: Async loading indicators ("Thinking...").
*   **`tty-markdown`**: Renders raw LLM markdown into ANSI-colored terminal text.

### 5. Concurrency & Streaming (`async`)
*   **Fiber 1**: `tty-spinner` animates.
*   **Fiber 2**: `ruby-openai` / `anthropic` streams SSE chunks from the LLM.
*   **Fiber 3**: Tool parser intercepts JSON tool calls, executes via `Open3`, and feeds stdo…

### 6. Background Tasks & Cron (`rufus-scheduler`)
For autonomous agent behavior (e.g., check email every 15m, summarize, append to Org-mode not…

## Handling Context & Memory (Without Vector DBs)
Instead of fragile native bindings like `sqlite-vss` or `lancedb`:
*   **Lexical Search**: Wrap `ripgrep` (`rg`) via `Open3`. Faster and more reliable for local…
*   **Knowledge Base**: Plain text Markdown or Org-mode (`kramdown` / `org-ruby`).
*   **State**: Simple `YAML` or stdlib `PStore`.

## Summary
This stack provides the robust routing of Go/Rust, the UI fidelity of Node's `ink`, and the n…

## Safety, Sandboxing & The Plugin Architecture

### 1. Sandbox Info via Config/Prompt
*   **Static Declaration**: Instead of complex autodetection, the sandbox environment/capabilities are declared via configuration or the initial prompt.
*   **Prompt Injection**: This state is dynamically injected into the LLM's system prompt so it understands the bounds of its environment (e.g., restricted access, missing tools) and doesn't attempt unsupported commands.

### 2. Hook-Driven Tool Execution (Powered by `dry-*`)
*   To keep the core ultra-lean, safety, loop prevention, and budget monitoring are modeled as plugins utilizing a robust middleware/hook pipeline.
*   **The Execution Pipeline**: Every tool execution is wrapped in hooks:
    `Trigger -> [Before Hooks] -> Execution -> [After Hooks]`
*   **Loop & Cost Safeguards as Plugins**:
    *   *Loop Guard*: Tracks repeated command patterns or consecutive error states to interrupt and alert the user.
    *   *Cost/Budget Guard*: Monitors token usage/spending and prompts for confirmation when session budgets are exceeded.

### 3. Plugin Trust & Future-Proofing
*   **Current Model**: Plugins are fully trusted and have full access.
*   **Future Design Space**: Maintain a hook/manifest capability where plugins can eventually declare their required permissions (e.g., `net`, `filesystem_write`, `db_write`) to allow capability-based sandboxing.

