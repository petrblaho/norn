# Norn Architectural Gaps & Refactoring Registry

This document catalogues the functional gaps, unaligned parts, and refactoring opportunities identified in the Norn codebase. It serves as an active backlog for incoming developers to align the implementation with the planned architectural specifications.

---

## 1. The MCP Integration Plan Gap

* **Specification Document:** `mcp_capabilities_security_plan.md`
* **Current Status:** 🔴 **Conceptual / Planned Only**
* **The Gap:** 
  The plan document details granular capability mapping, schema pruning, and pre-flight controls for Model Context Protocol (MCP) servers. However, **no MCP client, transport layer (such as SSE or Stdio), or server registries exist in the codebase**. 
* **Action Required:**
  1. Build a client/server abstraction conforming to the official MCP specification.
  2. Implement a standard IO/Stdio transport adapter to interface with external MCP servers.
  3. Register MCP tools dynamically inside the global `ToolRegistry` with appropriate capabilities mapped.

---

## 2. Missing Subprocess Execution Tool (`sys:execute`)

* **Specification Document:** `ARCHITECTURE.md` (Section 5)
* **Current Status:** 🟡 **Partially Specified, No Tool Implementation**
* **The Gap:**
  The system capability model registers a standard `sys:execute` permission level designated for high-risk operations like subprocess execution and shell commands. However, **there is no actual execution or bash command execution tool registered anywhere in the system**. The only registered tools are `file_read`, `file_write`, `file_edit`, `glob`, `grep`, and `prompt_user`.
* **Action Required:**
  1. Create a `subprocess_tools` or similar plugin under `plugins/`.
  2. Implement an `execute_command` or `bash` tool using secure standard-library utilities (e.g. `Open3.popen3`).
  3. Classify this tool under the `sys:execute` capability.
  4. Ensure it is statically declared as `dangerous: true` so it triggers the runtime gatekeeper.

---

## 3. Hardcoded LLM Client Configurations

* **Files:** `plugins/openai/client.rb` and `plugins/gemini/client.rb`
* **Current Status:** 🟡 **Refactoring Opportunity**
* **The Gap:**
  Specific configurations like default models (`gpt-4o-mini`, `gemini-3.5-flash`), temperature, max token limits, and target API versions are hardcoded directly within the client classes. This violates the dependency-injection and dynamic configuration loading pattern established in `lib/norn/config.rb` and `lib/norn/config_loader.rb`.
* **Action Required:**
  1. Extend `Norn::Config` settings in `lib/norn/config.rb` to support provider-specific parameters (e.g., `setting :openai_model`, `setting :gemini_model`).
  2. Add validation rules to `ConfigLoader::Schema` inside `lib/norn/config_loader.rb`.
  3. Inject the config values dynamically into the LLM client initializers.

---

## 4. Secret Scrubber Environment Key Inconsistencies

* **File:** `lib/norn/secret_scrubber.rb`
* **Current Status:** 🟡 **Minor Code Clean-up**
* **The Gap:**
  `Norn::SecretScrubber` is configured to dynamically discover and cache the environment key `NORN_PROVIDER_KEY` as a generic secret to redact. However, this environment key is never used or set up in the configuration loaders or LLM client classes (which strictly look for `OPENAI_API_KEY` and `GEMINI_API_KEY`).
* **Action Required:**
  * Clean up the unused reference or align the configuration system to allow `NORN_PROVIDER_KEY` as a unified alias for the active provider's API key.

---

## 5. Lack of End-to-End Integration & CLI Tests

* **Path:** `spec/`
* **Current Status:** 🔴 **Coverage Gap**
* **The Gap:**
  While the codebase maintains outstanding unit test coverage for its internal classes (`PluginManager`, `ToolRegistry`, `ConfigLoader`, `DiffHelper`, etc.), it lacks:
  1. End-to-End simulation tests for the main mode loops (`Chat`, `Dev`, `Task`).
  2. Integration tests that mock LLM API turn completions (simulating successive tool calls and responses).
  3. Executable testing verifying that command-line options are parsed and dispatched correctly in the final compiled script.
* **Action Required:**
  1. Create an E2E spec suite (e.g., `spec/norn/integration/`) that uses mock clients to simulate conversational turns.
  2. Add tests verifying `bin/norn`'s ARGV normalization engine.

---

## 6. OpenAI responses.create Call Formats

* **File:** `plugins/openai/client.rb`
* **Current Status:** 🟡 **Potential API Alignment Inconsistency**
* **The Gap:**
  In the OpenAI Client, messages are formatted using a payload format with the key `:input` (line 53):
  ```ruby
  params = {
    model: DEFAULT_MODEL,
    input: formatted_messages
  }
  ```
  And dispatched via:
  ```ruby
  response = openai_client.responses.create(**params)
  ```
  Typically, the official `ruby-openai` gem chat completion endpoints utilize the key `messages` rather than `input` (unless interfacing with specialized API assistants or embeddings). This is a point of potential alignment divergence that should be audited.
* **Action Required:**
  * Verify client compatibility with standard target API versions and refactor to use the typical `messages: formatted_messages` chat completion payload if necessary.
