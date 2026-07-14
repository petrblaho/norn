# Norn Comprehensive Audit & Expansion Plan

This document provides a highly detailed, structured, and actionable engineering roadmap for the Norn codebase. It evaluates recent developments, identifies gaps, and outlines precise tasks for documentation, test coverage, refactoring, CLI enhancements, help improvements, and introspection features.

---

## 1. Executive Summary & Context

Norn is a stateless, extensible, dynamic software engineering agent built in pure Ruby. Over the recent commits, the system has undergone massive feature expansion—transforming from a procedural, callback-based CLI prototype to a highly modular, Object-Oriented, railway-oriented application. 

### Core Architectural Pillars Verified:
1. **Capability-Based Sandboxing:** Granular permission models with pre-flight tool pruning and dynamic in-flight approval.
2. **Railway-Oriented Programming (ROP):** System pipelines orchestrated using `dry-monads` (`Success`/`Failure` tracks) to prevent cascading runtime crashes.
3. **Decoupled OO Plugin Engine:** Class-based plugin definitions with two-phase bootstrapping (hook declaration and auto-wired subscription).

---

## 2. Recent Development Audit (Today's Commits)

We audited the commit log representing recent additions. The findings and architectural significance of each commit are analyzed below:

### A. `fix/json encoding warning` (#14)
* **What changed:** Resolved `JSON.generate` encoding warnings during session serialization and LLM payload construction; centralized safety boundary sanitization within `Norn::Tool#call` via recursive UTF-8 forced encoding and scrubbing.
* **Architectural Impact:** Prevents crashes when reading from binary/compiled files or executing shell commands returning invalid UTF-8 bytes.

### B. `fix: separate dry-system root from workspace root` (#13)
* **What changed:** Decoupled `Norn::Container`'s system root path (where source code and plugins reside) from `Norn.workspace_root` (the user's execution directory).
* **Architectural Impact:** Ensures Norn boots and resolves its core files regardless of which subdirectory the CLI is executed from.

### C. `feat/instructions config` (#12)
* **What changed:** Introduced cascading LLM instructions with granular, level-by-level `clear` directives. Deleted legacy `instructions_override` properties.
* **Architectural Impact:** Allows local workspace configurations (`.norn.yml`) to cleanly inherit, override, prepend, or append to global/XDG rules.

### D. `refactor/rspec test helpers` (#11)
* **What changed:** Engineered a state-of-the-art testing harness including `IoSession` for standard stream mocking, custom matchers (`have_produced`, `have_produced_in_order`), and metadata-based plugin isolates (`norn_plugins: :some_plugin`).
* **Architectural Impact:** Future-proofs integration and E2E testing of multi-turn conversational loops.

### E. `feat/slash commands and plugins` (#8)
* **What changed:** Added an extensible, hook-based slash command registry inside the user-input middleware chain. Supported default commands `/exit`, `/quit`, `/clear`, and `/reset`.
* **Architectural Impact:** Allows third-party plugins to declare custom slash commands via the `:on_slash_commands_register` hook.

### F. `feat: add RSpec plugin` (#10)
* **What changed:** Added the `rspec` tool to run unit tests with automated `bundle exec` detection.
* **Architectural Impact:** Empowers the agent to run and verify its own tests.

### G. `feat: implement web_fetch tool` (#9)
* **What changed:** Developed a generic, SSL-safe HTML-to-Text retrieval utility that strips CSS/JS/SVG tags and truncates output to 12,000 characters.
* **Architectural Impact:** Allows web searching and external doc reading under the `:net_egress` capability.

### H. `refactor: chunk unified diff output` (#7)
* **What changed:** Enhanced `Norn::DiffHelper` to chunk unified diff outputs with context-awareness and clear line headers.
* **Architectural Impact:** Dramatically improves human readability during interactive change reviews.

---

## 3. Documentation Gap Analysis & Plan

While the codebase contains high-quality technical plans, the public-facing documentation has lagged behind the recent rapid feature additions.

### Gaps Identified:
1. **Cascading Instructions Config:** The exact configuration syntax of the new `instructions` schema is completely undocumented.
2. **Slash Commands:** The presence of interactive commands (`/exit`, `/clear`, etc.) and the hook system to register custom slash commands are undocumented.
3. **New Tools & Capabilities:** The `rspec` and `web_fetch` tools are not detailed, nor are their required capabilities (`:sys_execute`, `:net_egress`).
4. **Session Token Tracking:** The dynamic session tracking metrics printed in the console are not described.

### Action Plan:
- [ ] **Create `docs/CONFIGURATION.md`:** 
  - Detail the cascading instructions system, including an example of inheriting and clearing parameters:
    ```yaml
    # .norn.yml
    instructions:
      clear: ["prepend"]
      base: "Custom workspace-specific base prompt."
      append: ["Enforce tabs over spaces."]
    ```
- [ ] **Update `README.md` & `ONBOARDING.md`:**
  - Document all default slash commands (`/help`, `/exit`, `/quit`, `/clear`, `/reset`, `/tools`, `/session`).
  - Document how to extend slash commands using the `:on_slash_commands_register` hook:
    ```ruby
    Norn::PluginManager.subscribe(:on_slash_commands_register) do |registry|
      registry.register("/status", "Show git status") { |payload| ... }
    end
    ```
  - Document the unified tool catalog and their required capabilities (e.g. `file_read` -> `:sys_read`, `rspec` -> `:sys_execute`, `web_fetch` -> `:net_egress`).

---

## 4. Test Coverage Gap Analysis & Plan

Norn boasts an exceptional unit test suite (190 green specs), but several critical edge cases and security boundaries are currently untested.

### Gaps Identified:
1. **Subprocess/Argument Safety (Command Injection):** The `rspec` tool accepts custom `arguments` and `path` parameters. There are no test cases verifying protection against command injection (e.g. inject `; rm -rf /` or backticks).
2. **Config Errors:** Thin test coverage on how the config loader behaves when parsing malformed JSON/YAML or encountering completely invalid schema values.
3. **Escalation & Blocking in Non-Interactive Modes:** Verifying that a `Task` (non-interactive) mode execution *statically blocks* and fails gracefully when attempting to run a tool with unauthorized capabilities, without waiting for stdin.
4. **Web Redirect Loops:** Ensuring `web_fetch` handles infinite redirects or redirects to malformed hostnames gracefully. (Partially verified, needs deep-edge mocks).

### Action Plan:
- [ ] **Add Command Injection Specs:**
  - Add tests in `spec/plugins/rspec/plugin_spec.rb` to ensure arguments are escaped or restricted to prevent shell execution.
- [ ] **Add Malformed Config Specs:**
  - Add specs inside `spec/norn/config_loader_spec.rb` that simulate empty YAML files, invalid types, and confirm that standard warnings are output to stderr while reverting to safe defaults.
- [ ] **Add Interactive Escalation Specs:**
  - Build integration tests simulating user denial (`No`) or user approval (`Yes`) under capability escalations, verifying the state of the active mode's `allowed_capabilities`.

---

## 5. Refactoring Backlog & Recommendations

To maintain its "zero-debt" philosophy, Norn should address these identified technical refactoring opportunities:

### Recommended Refactorings:
1. **Extract `HtmlCleaner` from WebTools:**
   - *Current State:* `Fetcher.clean_html` contains regex replacements and character truncations.
   - *Action:* Extract to `Norn::Plugins::WebTools::HtmlCleaner` to allow clean, isolated testing of HTML formatting without mocking HTTP clients.
2. **Extract `SystemPromptCompiler` from `Norn::Mode`:**
   - *Current State:* Base mode class includes large blocks of code dedicated to merging sandbox configs, instructions, and tool execution directives.
   - *Action:* Move this to a standalone service `Norn::SystemPromptCompiler` for cleaner single-responsibility compliance.
3. **Extract `SanitizationHelper`:**
   - *Current State:* `Norn::Tool#sanitize_output` performs recursive string-scrubbing.
   - *Action:* Extract to `Norn::SanitizationHelper` so other serialization entry points (e.g., custom logging outputs) can share the same robust UTF-8 filtering.

---

## 6. CLI & Subcommand Additions Plan

Currently, Norn commands are dynamically generated only from registered Modes (`chat`, `dev`, `task`). The CLI is missing core developer utilities and options.

### Action Plan:
- [ ] **Add Global Version Flag (`--version`, `-v`):**
  - Define `lib/norn/version.rb` containing `Norn::VERSION = "1.0.0"`.
  - Add the `--version` flag into global argument handling inside `bin/norn` or `lib/norn/global_options.rb` to display the version and exit immediately.
- [ ] **Introduce `norn config` Subcommand:**
  - Build a custom dry-cli command to display active configurations:
    ```bash
    $ norn config
    Active LLM Provider: openai (model: gpt-4o-mini)
    Global Config Path:  ~/.config/norn/config.yml (Not Found)
    Local Config Path:   ./.norn.yml (Active)
    ```
- [ ] **Introduce `norn diagnose` Subcommand:**
  - Perform environment diagnostic checks (API keys presence, internet connectivity, tool registrations).

---

## 7. Introspection & Developer Tools Plan

Introspection allows both the agent and the human operator to view the internal metadata of the system.

### Achievements (Completed Today!):
We successfully implemented and tested live interactive introspection slash commands:
* **`/tools`:** Outputs a beautiful, ANSI-colored list of all registered tools, their descriptions, required capabilities, and dynamic danger warning markers.
* **`/session`:** Displays high-fidelity, real-time statistics of prompt tokens, completion tokens, total tokens, and tool calls.

### Future Introspection Additions:
- [ ] **Add `/plugins` Slash Command:**
  - Outputs a list of all loaded plugin classes and their current lifecycle statuses.
- [ ] **Add `/hooks` Slash Command:**
  - Visualizes Norn's active hook subscription graph, showing which plugins listen to which hook events (e.g., `:on_user_input`, `:on_render_response`) and their execution sequence.
- [ ] **LLM Self-Introspection Prompting:**
  - Insert a lightweight system prompt rule instructing the LLM to run `/tools` or `/session` (by calling the corresponding introspection tools) whenever the user asks about the agent's capabilities or token consumption.

---

## 8. Help & Interactive UX Improvements

Norn can provide a much warmer, more guided user experience during startup and command usage.

### Achievements (Completed Today!):
* Modified the interactive startup banner inside `lib/norn/mode.rb` to explicitly guide users to type `/help` for access to our new slash commands.

### Future UX Improvements:
- [ ] **Create a Dynamic Tabular Formatter:**
  - Replace raw spacing formatting in `/help` and `/tools` with a clean, grid-aligned column renderer.
- [ ] **Build a Collapsible Content Utility:**
  - Implement **Approach A** from `collapsible_terminal_outputs_plan.md` to cleanly wrap very long tool outputs (like full file reads or large diffs) in a keyboard-foldable inline header.
