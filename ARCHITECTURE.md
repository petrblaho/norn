# Norn Architecture, Techniques, & Coding Practices Manual

Welcome to the Norn Architecture and Engineering Manual. This document serves as the primary technical specification of Norn's core system architecture, design decisions, safety mechanics, and coding standards.

---

## 1. Core Architectural Philosophy

Norn is built as a **stateless, extensible, dynamic software engineering agent**. Its engineering decisions are guided by three core pillars:

1. **Zero Native C-Dependency Bindings:** Eliminates installation fragility and cross-compilation failures (e.g., `node-gyp` compilation errors, SQLite/LanceDB ABI mismatches, OpenSSL library clashes) by relying entirely on Ruby's robust standard library and stable pure-Ruby gems.
2. **Object-Oriented Plugin-Centric Extension:** All major subsystems are completely decoupled. External LLM clients, tool libraries, and custom UI renderers register dynamically as self-contained classes.
3. **Fail-Fast Bootstrapping:** Interface contracts and subclassing dependencies are verified at load time rather than deep inside runtime loops, ensuring any development or configuration error is caught immediately during startup.

---

## 2. Dependency Injection & Core Bootstrap Layout

Norn avoids global state and singleton class structures by managing all components through a central Dependency Injection (DI) Container powered by the `dry-rb` ecosystem.

```
                        ┌────────────────────────┐
                        │        bin/norn        │
                        └───────────┬────────────┘
                                    │
                                    ▼
                        ┌────────────────────────┐
                        │   ConfigLoader.load    │
                        └───────────┬────────────┘
                                    │
                                    ▼
                        ┌────────────────────────┐
                        │  PluginLoader.load_all │
                        └───────────┬────────────┘
                                    │
                                    ▼
                        ┌────────────────────────┐
                        │   Normalize ARGV!      │
                        └───────────┬────────────┘
                                    │
                                    ▼
                        ┌────────────────────────┐
                        │   Dry::CLI Dispatch    │
                        └────────────────────────┘
```

### The DI Container (`lib/norn/container.rb`)
* `Norn::Container` inherits from `Dry::System::Container` and manages standard components (like LLM clients under `llm.openai` or `llm.gemini`).
* Resolving clients dynamically from the container decouples the command loop from specific API clients:
  ```ruby
  client = Norn::Container["llm.#{provider}"]
  ```

### Dynamic Global Options Registry (`lib/norn/global_options.rb`)
To avoid hardcoding flags (like `--provider` or `--debug`) in Norn's core, external plugins can register their own command-line options dynamically during bootstrapping:
```ruby
Norn::GlobalOptions.register :provider, 
                             type: :string, 
                             aliases: ["-p"], 
                             desc: "LLM provider to use"
```

### Flexible ARGV Normalization (`bin/norn`)
To bypass `dry-cli`'s strict command-order limitations (which usually forces options *after* subcommands), an early-boot normalizer scans `ARGV`, maps registered global options dynamically, and moves them to the end of the argument array prior to dispatching:
`./bin/norn --provider gemini chat` $\rightarrow$ `./bin/norn chat --provider gemini`

---

## 3. Class-Based Plugin System (`lib/norn/plugin.rb`)

Norn's dynamic extensibility is powered by Object-Oriented class inheritance. 

### The Subclass Registry Hook
```ruby
module Norn
  class Plugin
    @registered_plugins = []

    def self.inherited(subclass)
      super
      @registered_plugins << subclass
    end

    def self.registered_plugins
      @registered_plugins
    end
  end
end
```
Any file loaded by the `PluginLoader` that subclasses `Norn::Plugin` is automatically registered in-memory on require.

### Hook-Bridging Dispatcher (`lib/norn/plugin_manager.rb`)
The `PluginManager` acts as a hybrid event-bus. When a lifecycle event is triggered (such as `:on_boot`, `:on_tool_register`, or `:on_render_response`), the manager:
1. Executes all legacy block-based subscriptions registered via `subscribe`.
2. Dynamically routes calls to matching instance methods on active `Norn::Plugin` objects, bridging OO designs with event-driven pipelines seamlessly.

---

## 4. Railway-Oriented Programming (ROP) in Ruby

To eliminate fragile nested `begin/rescue/raise` loops, Norn implements **Railway-Oriented Programming** using `dry-monads` and `Dry::Monads::Do` notation.

```
Success track ──[Load Config]───►[Resolve Client]───►[LLM Call]───►[Execute Tool]──► Success(output)
                      │                 │               │               │
Failure track ────────┴─────────────────┴───────────────┴───────────────┴──────────► Failure(payload)
```

### The Result Monad Pipeline
Every service, configuration loader, and LLM client returns a monadic `Result` (`Success` or `Failure`):
```ruby
# Example of flat, failure-safe loop execution in task.rb
def execute_loop_step(system_prompt)
  client = yield resolve_provider_client(Norn.config.llm_provider)
  
  response_result = client.call(active_messages, tools: Norn::ToolRegistry.registered_tools)
  response = yield response_result.alt_map { |payload| payload.with_context(step: :llm_call) }

  # ... proceed on the success track safely ...
end
```

### Contextual Failures (`lib/norn/errors.rb`)
Instead of propagating raw, unhelpful string messages, failures are wrapped inside a structured `Norn::FailurePayload`. This payload holds:
* The original Ruby exception object (preserving stack traces).
* A rich `context` Hash capturing the state (e.g., active provider, active prompt, step, original HTTP payloads) at the exact moment of failure, allowing for deep, diagnostic debugging.

---

## 5. Security & Capability-Based Sandboxing

Norn implements a strict, robust **Capability-Based Security Model** to govern tool-calling and parameter accessibility:

```
[Agent Session Starts]
        │
        ├─► Pre-Flight Pruning: Only expose authorized tool schemas to LLM.
        │
        ▼
[LLM decides to call a Tool]
        │
        ├─► In-Flight Gatekeeper: Evaluate required capabilities dynamically.
        │
        ├─► If Authorized: Execute tool.
        │
        └─► If Unauthorized:
                 ├─► If Mode.interactive? ──► Prompt CLI for Y/N escalation.
                 └─► If Non-Interactive  ──► Fail-Safe Block & return Failure.
```

### Standard Capabilities
* `sys:read`: Read-only local file operations (`file_read`, `glob`, `grep`, `prompt_user`).
* `sys:write`: Local filesystem writes and edits (`file_write`, `file_edit`).
* `sys:execute`: Subprocess executions and local command lines.

### Safe Chat Mode Tools
By classifying tools like `file_read`, `glob`, `grep`, and `prompt_user` under `sys:read` and restricting Chat Mode's permitted capabilities to `[:sys_read, :vcs_read]`, **Chat Mode is securely empowered with read-only capabilities.** 

Chat Mode dynamically maps, reads, and explains files within your codebase safely without any risk of file corruption or write modifications.

### Pre-Flight Schema Pruning
Before invoking any LLM provider client, Norn selectively filters out any tool whose required capabilities exceed the active mode's permitted profile. This prevents the model from wasting tokens trying to call completely forbidden tools.

### Centralized In-Flight Gatekeeper (`lib/norn/mode.rb`)
Every mode inherits a secure `#execute_tool` block:
* If a tool requires unauthorized capabilities in an `interactive?` mode, Norn prompts the user on the CLI for **real-time escalation (Y/N)**. If approved, the permission is temporarily cached for that session.
* In non-interactive modes, Norn **blocks by default** and aborts execution immediately with a `Failure` monad.

---

## 6. Dynamic In-Flight Danger Guards & Diff Previews

For interactive coding workflows, Norn features a **Dynamic Parametric Danger Gatekeeper** to safeguard your local codebase from unintended modifications.

### Parametric Danger Checking
Tools can be statically designated as dangerous (like `file_write` or `file_edit`) or dynamically override `#dangerous?(args)` to evaluate their parameters at runtime (e.g. blocking destructive version-control resets while allowing safe status queries).

### Unified Diff Color Helper (`lib/norn/diff_helper.rb`)
When a dangerous write/edit tool is triggered in an interactive mode, Norn halts execution and:
1. Resolves the proposed file modifications.
2. Computes a lightweight, pure-Ruby, unified line diff.
3. Renders the changes with **bold ANSI terminal formatting** (red `-` for removals, green `+` for additions) to let you audit the edits.
4. Intercepts terminal input, defaulting to **Yes/Approval** if the user presses Enter immediately (`[Y/n]` prompt) or aborting cleanly on `n`.

---

## 7. Interactive Pairing & Pairing Mode (`lib/norn/modes/dev.rb`)

To bring these features together under an optimal developer workflow, Norn features **Interactive Dev Mode** (`Norn::Modes::Dev`), triggered via `./bin/norn dev`.

* **The Strategy:** Conforms to our full subclassing contracts, carrying full development capabilities (`[:sys_read, :sys_write, :sys_execute, :vcs_read, :vcs_write, :net_egress]`).
* **The Interaction:** Operates as a live REPL pairing loop. Because it is `interactive?`, all dangerous tool calls (like writing code or running shell scripts) triggered by Gemini/OpenAI are automatically intercepted in-flight by **Section 6 danger guards**, printing diffs and prompting for validation right in your console before execution.

---

## 8. Dynamic Tool-Level System Instruction Injection

To maintain clean plugin decoupling, Norn implements **dynamic system prompt injection**. 

### Decentralized Directives
Instead of hardcoding tool-use guidelines inside core files, **each tool defines its own instructions** upon initialization inside its respective plugin:
```ruby
Norn::Tool.new(
  "prompt_user",
  "Prompt the user...",
  SCHEMA_JSON,
  system_instructions: "If a user instruction is ambiguous, call the 'prompt_user' tool to obtain structured feedback..."
)
```

### In-Flight Prompt Compilation (`lib/norn/mode.rb`)
Before dispatching a conversational turn to the LLM client, Norn calls `#compile_system_prompt` on the active Mode:
1. It identifies all tools **currently authorized** for the active Mode.
2. It collects only those tools' `system_instructions` and joins them under a clean `TOOL EXECUTION DIRECTIVES` block.
3. It appends this list to the core mode instructions and passes the fully-grounded instructions to the provider, keeping the LLM perfectly aware of its dynamic capabilities on every turn.

---

## 9. Interactive Prompts & The PromptUser Plugin

To empower the LLM with the ability to query, ask, and present choices to the developer programmatically, Norn introduces the **`PromptUser` Plugin** (`plugins/prompt_user/plugin.rb`).

* **Widgets Supported:** Maps the `"prompt_user"` tool directly to native, highly styled terminal elements via `TTY::Prompt`:
  - `confirm`: Colored binary selector (`yes`/`no`).
  - `select`: Multi-option cursor selector. Fully supports **explicit single-turn custom write-ins** via the `allow_custom` parameter, which dynamically appends a `"Custom (type your own...)"` option and prompts for inline text input in a single, frictionless conversational step.
  - `multi_select`: Spacebar checkbox option selector.
  - `input`: Free-text interactive input.
* **Context Passing:** The Mode execution gatekeeper passes `self` (the active `Mode` instance) as the `context` parameter to the tool's block execution, enabling the plugin to cleanly access the REPL's `@input` and `@output` streams in a fully stateless, thread-safe manner.

---

## 10. Dynamic Hook Policies & Recovery Track

We standardize Norn's lifecycle hooks and plugin events into two distinct categories:

### A. Notifications (Parallel / Fire-and-Forget)
Informational events that do not mutate state and execute in parallel (e.g., `:after_llm_call`).

### B. Middlewares (Sequential ROP / Kleisli Reduction)
Mutating pipelines where the output of one subscriber becomes the input of the next. The entire chain is wrapped in the `Success/Failure` monad track using a monadic `reduce` composed of `bind` operations.

### Recoverable Fail-Safe Policies (`lib/norn/plugin.rb`)
Plugins can declare their hook policies as `:recover` (recoverable/non-fatal) or `:fatal` (the default). If an optional `:recover` subscriber fails or throws an exception (such as `TTYMarkdownPlugin` parsing), Norn logs a dim grey console warning (`[Norn Warning] Optional hook... failed`) and safely recovers the pipeline, passing the last valid success payload forward.

---

## 11. Security & In-Memory Secret Scrubbing

Norn operates a strict, multi-layered security model to ensure sensitive developer tokens (such as Gemini or OpenAI keys) are never leaked to logs, CLI traces, or API queries.

### Multi-Layer Token Redactor (`lib/norn/secret_scrubber.rb`)
1. **Dynamic Caching:** When Norn starts up, it registers standard environment keys in-memory. When processing any string, it scans for pattern matches (like Google `key=...` query params or OpenAI `sk-...` signatures), extracts the raw keys, and adds them to a secure in-memory `Set`.
2. **Deep-Sanitization (`Norn::FailurePayload`):** Raw exceptions (such as `Faraday::BadRequestError`) are recursively traversed. Non-basic objects (like exception variables containing the raw request params with the API keys) are converted to string representations and sanitized before the context is stored.
3. **Console Boundary Protection (`Norn::ErrorRenderer`):** Just before debug metrics or backtraces are written to standard error, they are scrubbed of all registered secret values.

---

## 12. Multimodal Part Preservation

Gemini's conversation structure relies on an array of `parts` where reasoning chains (thought signatures) and `functionCall` blocks are logically bound.

* **Unified Message Schema:** To prevent structure violations (`INVALID_ARGUMENT: Function call is missing a thought_signature`), the Gemini client extracts and returns the raw API response `parts` in the `Success` monad.
* **History Preservation:** The `Task` and `Chat` mode loops capture these raw `:parts` and store them in the conversation history, which the Gemini adapter echoes back exactly as received on subsequent turns, keeping Google's backend integrity checks satisfied without polluting other provider formats (like OpenAI).

---

## 13. Coding Practices & Testing Standards

1. **TDD Interface Isolation:** Unit tests (`rspec`) must mock external API requests to return monadic results (`Success(...)` / `Failure(...)`) to ensure perfect compatibility with ROP pipelines.
2. **Dynamic Spec Cleanups:** Test states are strictly isolated using `config.before(:each)` hooks inside `spec_helper.rb` to clear the `ToolRegistry`, `Plugin.registered_plugins`, and `PluginManager` state.
3. **Efficiency Overriding:** Directives are explicitly tuned to command immediate writes on file creation requests, preventing the LLM from executing redundant, token-heavy filesystem searches or double-reading files back from disk.
