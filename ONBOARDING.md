# Norn Onboarding & Developer Reference Manual

Welcome to Norn! As the outgoing senior contractor on this project, I have compiled this comprehensive manual to get you up and running as fast as possible. 

Norn is a **stateless, extensible, dynamic software engineering agent** written in pure Ruby. It is built to be fast, secure, dependency-stable, and extremely robust. It avoids standard AI agent fragilities (like bloated JS/Python dependency trees, native C-dependency compilation failures, and fragile global states) by using Ruby's standard library and a highly structured, object-oriented, monadic architecture.

This document outlines the core architecture, key engineering approaches, identified missing or unaligned parts, and a step-by-step onboarding guide.

---

## 1. Architectural Blueprint & Core Subsystems

Norn's boot sequence and run loop follow a strict decoupled lifecycle:

```
                  +--------------------------------+
                  |            bin/norn            |  <-- Entry Point
                  +--------------------------------+
                                  |
                                  v
                  +--------------------------------+
                  |      Norn::ConfigLoader        |  <-- 1. Loads Configuration
                  +--------------------------------+      (XDG -> Local .norn -> ENV)
                                  |
                                  v
                  +--------------------------------+
                  |      Norn::PluginLoader        |  <-- 2. Scans plugins/ & requires plugin.rb
                  +--------------------------------+
                                  |
                                  v
                  +--------------------------------+
                  |      Norn::PluginManager       |  <-- 3. Instantiates Plugin classes,
                  +--------------------------------+      declares hooks & triggers :on_boot
                                  |
                                  v
                  +--------------------------------+
                  |       Norn::Container          |  <-- 4. Registers services & Finalizes (dry-system)
                  +--------------------------------+
                                  |
                                  v
                  +--------------------------------+
                  |         Norn::CLI              |  <-- 5. Registers CLI commands dynamically
                  +--------------------------------+      for each registered Mode (dry-cli)
                                  |
                                  v
                  +--------------------------------+
                  |       Argument Normalizer      |  <-- 6. Moves global options to end of ARGV
                  +--------------------------------+
                                  |
                                  v
                  +--------------------------------+
                  |       Dry::CLI Dispatch        |  <-- 7. Routes to active Mode
                  +--------------------------------+
```

Once a Command is dispatched, it resolves its execution Mode class (e.g. `Dev`, `Chat`, `Task`), compiles the unified security system prompt, and starts the REPL or single-turn loop.

### Subsystem Directory Layout

* **`bin/norn`**: Early-boot configuration loader, plugin auto-wirer, CLI dispatcher, and argument normalizer.
* **`lib/norn/`**:
  * `container.rb`: The service locator / DI container powered by `dry-system`.
  * `config.rb` & `config_loader.rb`: Hierarchical configurator utilizing `dry-configurable` and `dry-schema`.
  * `plugin.rb`, `plugin_loader.rb`, `plugin_manager.rb`: The object-oriented class registration and hybrid event-bus/middleware hook dispatcher.
  * `mode.rb` & `mode_registry.rb`: Abstract template for operational modes and their registration.
  * `tool.rb` & `tool_registry.rb`: Unified tool modeling, capability evaluation, dynamic instructions, and registry.
  * `errors.rb` & `error_renderer.rb`: Structured monadic failure context and redacting.
  * `secret_scrubber.rb`: In-memory multi-layer security regex scanner and dynamic token redactor.
  * `diff_helper.rb`: Lightweight, dependency-free LCS unified diff previewer with ANSI coloring.
* **`plugins/`**:
  * `file_tools/`: File system utilities (`file_read`, `file_write`, `file_edit`, `glob`, `grep`).
  * `prompt_user/`: Interactive terminal prompts (`confirm`, `select`, `multi_select`, `input`) powered by `tty-prompt`.
  * `tty_markdown/`: Markdown terminal rendering pipeline hook powered by `tty-markdown`.
  * `openai/` & `gemini/`: Stateless translators and clients wrapping `ruby-openai` and `gemini-ai` respectively.

---

## 2. Core Engineering Paradigms (Our Architectural Pillars)

When writing code in Norn, you must strictly respect and follow these five pillars:

### A. Railway-Oriented Programming (ROP)
To prevent unhandled runtime crashes, nested retry loops, and code smell, Norn uses `dry-monads` (`Success` and `Failure` Results).
* **Always return a Monad Result** from service calls, clients, and pipelines.
* Use `dry-monads`' `Do` notation (`yield`) to flat-map multi-step execution chains cleanly.
* Wrap errors inside `Norn::FailurePayload` to automatically bundle rich state diagnostics and trigger redactors.

### B. Decoupled Dependency Injection
Never hardcode or instantiate global singletons.
* Register LLM clients, databases, or shared state elements inside `Norn::Container` during the `:on_boot` hook.
* Resolve services dynamically: `Norn::Container["llm.#{provider}"]`.

### C. Capability-Based Sandboxing
Norn operates a strict, dual-layer security model to govern tool calls.
* **Layer 1 (Pre-Flight):** Only tools whose required capabilities (e.g. `[:sys_read]`) match the active mode's permitted profile are exposed in the JSON schema sent to the LLM.
* **Layer 2 (In-Flight Gatekeeper):** When a tool is triggered, its required capabilities are evaluated dynamically (`Tool#capabilities_for(args)`). If any missing permissions are detected:
  * In **Interactive Modes** (`interactive? == true`), the engine halts and prints a security escalation prompt `[y/N]`. If approved, capabilities are temporarily cached.
  * In **Non-Interactive Modes**, the engine **blocks by default** and aborts cleanly with a monadic `Failure`.

### D. In-Flight Danger Guards & Diff Previews
* Tools can designate themselves as `dangerous: true` statically or dynamically override `#dangerous?(args)` based on parameters.
* When a dangerous filesystem mutation (like `file_write` or `file_edit`) is triggered in interactive mode, Norn halts and uses `Norn::DiffHelper` to compute a colored, LCS line-by-line diff.
* The user is prompted `[Y/n]` to apply changes (with Enter defaulting to Yes).

### E. In-Memory Secret Scrubbing
Norn intercepts and scrubs raw developer credentials recursively.
* On boot, `SecretScrubber` discovers keys in `ENV` (`OPENAI_API_KEY`, `GEMINI_API_KEY`) and adds them to a secure in-memory `Set`.
* As strings flow through `Norn::FailurePayload` or the `ErrorRenderer`, the scrubber scans them via pattern matches, registers any newly discovered secrets dynamically, and replaces them with `[REDACTED]` or `sk-...[REDACTED]`.

---

## 3. Walkthrough of Main Files & Contracts

### The Plugin Contract (`lib/norn/plugin.rb`)
Subclassing `Norn::Plugin` automatically hooks the class into the subclass memory registry.
```ruby
class MyPlugin < Norn::Plugin
  def self.plugin_name
    "my_plugin"
  end

  def on_boot(container)
    # Register components to dry-system
  end

  def on_tool_register(registry)
    # Populate the global ToolRegistry
  end
end
```

### The Mode Contract (`lib/norn/mode.rb`)
Every operational mode registers in `Norn::ModeRegistry`:
```ruby
class MyMode < Norn::Mode
  def interactive?; true; end
  def allowed_capabilities; [:sys_read]; end
  def instructions; "System instructions for this mode"; end
  def banner_name; "My Mode"; end
end
Norn::ModeRegistry.register("mymode", MyMode, description: "Run my mode")
```

---

## 4. Unaligned Parts & Identified Gaps (The Developer TODO List)

As you begin your work on the codebase, be aware of several gaps where the implementation deviates from the planned design or leaves room for optimization:

1. **The MCP Plan Gap (`mcp_capabilities_security_plan.md`)**:
   * *Status:* **Conceptual Only.**
   * *The Gap:* The plan document outlines highly advanced security models for Model Context Protocol (MCP) servers, but there is absolutely no MCP client, transport layer (SSE/Stdio), or registry implemented in the codebase yet.
2. **Missing Execute Tool**:
   * *Status:* **Missing Tool.**
   * *The Gap:* The architecture details a `sys:execute` capability (subprocess execution, local CLI commands). However, there is no corresponding `bash` or `execute_command` tool registered anywhere in the `file_tools` or other plugins! The capability exists in security models but has no actual executable tool.
3. **Hardcoded LLM Specifics**:
   * *Status:* **Refactoring Opportunity.**
   * *The Gap:* Configuration options like model names (e.g. `gpt-4o-mini`, `gemini-3.5-flash`), temperature, and max tokens are hardcoded inside `plugins/openai/client.rb` and `plugins/gemini/client.rb`. They should be moved to settings inside `lib/norn/config.rb` and schema-validated by `ConfigLoader`.
4. **Scrubber / Key Inconsistencies**:
   * *Status:* **Minor Clean-up.**
   * *The Gap:* `SecretScrubber` attempts to automatically cache `NORN_PROVIDER_KEY`, but this environment variable is never set up or mapped to client keys anywhere else in the configuration bootstrap.
5. **Lack of Integration and CLI Command Tests**:
   * *Status:* **Testing Gap.**
   * *The Gap:* Although unit coverage is excellent, there are no end-to-end integration tests that mock external LLM API turns or verify that the compiled executable (`bin/norn`) dispatches options and arguments correctly.
6. **Agent Skills Support Integration**:
   * *Status:* **Specification Planned.**
   * *The Gap:* Norn needs native support for the Agent Skills specification (https://agentskills.io/) to discover, parse, and progressively disclose modular `.agents/skills/` capabilities at both project and user-level directory scopes.

---

## 5. Newbie Step-by-Step Task & Onboarding Guide

To get your development workflow fully validated, perform these steps in order:

### Step 1: Install Dependencies
Ensure you have Ruby installed. Run:
```bash
bundle install
```

### Step 2: Set Up Environment Variables
Create a local `.env` file in the project root:
```env
OPENAI_API_KEY=sk-...your-actual-key-if-available...
GEMINI_API_KEY=AIzaSy...your-gemini-key...
NORN_PROVIDER=openai  # or gemini
```

### Step 3: Run the Test Suite
Ensure all unit tests pass:
```bash
bundle exec rspec
```

### Step 4: Run the CLI in Chat Mode
Launch the interactive read-only Chat mode to explore the codebase:
```bash
./bin/norn chat
```
Ask: `Who are you?` or `Find all ruby files in the codebase`. Note how Norn uses `glob` and `file_read` under the hood!

### Step 5: Run the CLI in Dev Mode
Launch the full write-access developer pairing REPL:
```bash
./bin/norn dev
```
Ask Norn to write a dummy text file to see the interactive **Diff Previewer** and **Danger Guard** prompt in action!

---

Good luck! You are stepping into an exceptionally clean, well-factored, and modern Ruby codebase. Let me know if you have any questions before I hand off completely!
