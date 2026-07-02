# Norn Capability-Based Security & Interactivity Plan

**Implementation Status:** ✅ **Fully Implemented & Verified (July 2, 2026)**

This document outlines the architectural plan and actual implementation details for Norn's granular, parametric security model. It is designed to scale dynamically for future integrations like Model Context Protocol (MCP) servers, multi-agent workflows, and secure, read-only Chat Mode tools.

---

## 1. System Capabilities (Permissions)

Norn defines a granular set of system permissions (capabilities) instead of a binary "harmless vs. harmful" designation:

| Capability | Description | Risk Level |
| :--- | :--- | :--- |
| `sys:read` | Reading local workspace state and file contents. | **Safe** |
| `sys:write` | Creating, modifying, or deleting local files. | **Medium** |
| `sys:execute` | Invoking local subprocesses or CLI binaries. | **High** |
| `net:egress` | Outbound network connections or API requests. | **Medium-High** |
| `vcs:read` | Querying version control status or logs (e.g., `git status`, `git diff`). | **Safe** |
| `vcs:write` | Modifying version control history or state (e.g., `git commit`, `git checkout`). | **Medium** |
| `vcs:network` | Pushing to or pulling from remote repositories (e.g., `git push`, `git fetch`).| **High** |

---

## 2. Dynamic Parametric Capability Resolution

A tool does not carry a static capability level. Instead, a tool dynamically evaluates its arguments at runtime to determine what capability is required.

### Example: Git Tool Parametric Mapping
When `git` is executed with specific arguments:
* `git status`, `git diff` $\rightarrow$ resolves to `[:vcs_read, :sys_read]`
* `git commit`, `git checkout` $\rightarrow$ resolves to `[:vcs_write, :sys_write]`
* `git push`, `git fetch` $\rightarrow$ resolves to `[:vcs_write, :net_egress]`
* Any unrecognized command $\rightarrow$ defaults to `[:sys_execute]` (Absolute Safety)

---

## 3. Dual-Layer Enforcements

To ensure absolute security while helping the LLM navigate its boundaries efficiently, we employ a **dual-layer defense-in-depth model**:

### Layer 1: Pre-Flight Enforcements (Pruning & Informing)
Before sending the list of tools to the LLM client:
1. **Omission:** If a tool's minimum capabilities are completely unauthorized by the active Mode's profile, the tool is entirely removed from the schema sent to the API.
2. **Schema Pruning (Parameter Restriction):** If a tool has parametric options (like a subcommand enum in `git`), Norn dynamically rewrites its JSON Schema parameters to remove unauthorized parameters (e.g., removing `"push"` and `"commit"` from the subcommand list when in Chat Mode).
3. **System Prompt Grounding:** A dynamically generated security summary is appended to the system instructions, informing the model of its active sandbox permissions (e.g., *"Active permissions: sys:read, vcs:read. You can inspect code but cannot write files or execute bash commands"*).

### Layer 2: In-Flight Runtime Guard (The Gatekeeper)
Just before actual execution inside `Norn::Tool#call`:
1. Norn resolves the exact, live capabilities required for the provided arguments.
2. Norn checks the resolved capabilities against the active Mode's/Agent's profile.
3. If an unauthorized capability is requested, Norn applies the **Interactivity Policy**.

---

## 4. Mode Interactivity Profiles

We categorize Norn's modes by their **Interactivity Profile**, which dictates how authorization failures are handled at runtime:

### A. Interactive Modes (e.g., `Chat` Mode, Interactive prompt)
* If an unauthorized capability is requested, Norn halts execution and prompts the user on the CLI for real-time, runtime escalation:
  ```
  ⚠️ Warning: The agent is trying to run `git push` which requires the `net:egress` capability. 
  Do you want to authorize this? [y/N]: 
  ```
* **Approved:** Executed, and the authorization is cached for the remainder of the session.
* **Rejected:** Blocked, and a structured, safe failure message is returned to the LLM (*"The user denied authorization to execute this command"*).

### B. Non-Interactive Modes (e.g., Background tasks, CI/CD jobs)
* **Block by default.** If a capability is unauthorized, Norn immediately blocks execution, logs the security violation, and returns a monadic `Failure(Norn::FailurePayload)` error, preventing any hanging or waiting on headless stdin.

---

## 5. Implementation Architecture & Source Code

### A. Core Tool Model (`lib/norn/tool.rb`)
Enforces static capabilities and exposes parametric evaluation:
```ruby
class Tool
  attr_reader :name, :description, :parameters, :block, :required_capabilities

  def initialize(name, description, parameters, required_capabilities: [:sys_execute], &block)
    @name = name.to_s
    @description = description
    @parameters = parameters
    @required_capabilities = Array(required_capabilities)
    @block = block
  end

  def capabilities_for(args = {})
    @required_capabilities
  end
end
```

### B. Centralized Gatekeeper (`lib/norn/mode.rb`)
Unifies capability checks, Y/N prompt prompts, and execution rules under a single, robust method:
```ruby
def execute_tool(tool_name, args)
  tool = Norn::ToolRegistry.resolve(tool_name)
  return Success(...) if tool.nil? # handle missing tool

  required_caps = tool.capabilities_for(args)
  missing_caps = required_caps - allowed_capabilities

  if missing_caps.empty?
    # Proceed to call
    Success(tool.call(args).to_s)
  elsif interactive?
    # Prompt user...
  else
    # Block and return Failure payload
  end
end
```
