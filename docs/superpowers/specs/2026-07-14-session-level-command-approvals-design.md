# Design Spec: In-Memory Session Approvals with Safe Command Pattern Matching

- **Date**: 2026-07-14
- **Status**: Approved
- **Target Card**: Card 5 (Implement In-Memory Session Approvals with Safe Command Pattern Matching)

---

## 1. Context & Business Case

When using Norn in interactive modes (like Chat or Dev Mode), executing multiple safe commands successively (e.g. `git status`, `git diff`, `git log`) under capability-based security results in severe **prompt fatigue**. The user must repeatedly approve similar operations.

To solve this, we will implement an in-memory **Session-Level Command Approval** option. However, blindly whitelisting all subsequent executions poses extreme security risks. Instead, Norn must dynamically decompose command payloads and inspect their parameters against tool-encapsulated safety boundaries. Safe subcommands will be auto-approved, while dangerous operations (e.g. `git push`, `git commit`, `rm -rf`) must statically bypass session caching and prompt the user for explicit authorization.

---

## 2. Architectural Design & Tool Boundaries

To prevent framework coupling and uphold the Open-Closed Principle, core orchestrators like `Norn::Mode` or `Norn::UI::Gatekeeper` will not contain hardcoded subcommand filters (e.g. no checks for `git`). Instead, we define a generic **Tool-Level Session Approval Contract** on the base `Norn::Tool` class.

```
                  Norn::Mode (Orchestrator)
                         │
                         ├─► Norn["session"] (Read approvals)
                         ▼
               Norn::Tool (API Contract)
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
   Base Tool Class                     GitTool
- session_approved?                - dangerous?(args) [custom]
- session_approval_label           - session_approval_label [custom]
- session_approval_pattern
```

### 2.1 The Tool API Contract (`Norn::Tool`)
We add the following standard methods with robust fallback defaults:

1. `session_approval_label(args)`: Returns a display string for the interactive selection menu (e.g. `"Approve 'git <subcommand>' for the rest of this session"`).
2. `session_approval_pattern(args)`: Generates the structured pattern hash to cache in the active session (e.g. `{ tool_name: name }`).
3. `session_approved?(session, args)`: Determines if the incoming execution with specific arguments matches a cached session approval AND does not violate safety boundaries:
   ```ruby
   def session_approved?(session, args)
     return false if session.nil?
     approvals = session.get(:session_approvals) || []
     has_approval = approvals.any? { |app| app[:tool_name] == name }
     has_approval && !dangerous?(args)
   end
   ```

### 2.2 Tool Specialization: `GitTool`
Because `Norn::Plugins::Git::GitTool` already implements `dangerous?(args)` to detect destructive subcommands (like `commit`, `push`, `add`, force checkouts, and hard resets), it automatically gets safe subcommand filtering via the base `session_approved?` contract. We only override `session_approval_label` to return the customized text.

---

## 3. Detailed Data & Execution Flows

### 3.1 Pre-Flight Session Approval Evaluation
Before triggering the Gatekeeper UI inside `Norn::Mode#execute_tool`:
1. Check if an active session is available via `Norn["session"]`.
2. Invoke `tool.session_approved?(session, args)`.
3. If `true`:
   - Print a visible notification: `⚡ Session approved: <tool_name> <arguments>` to stdout.
   - Execute the tool block directly, bypassing both capability and danger prompts!
4. If `false`:
   - Proceed through standard capability and interactive danger gatekeeping.

### 3.2 Caching Approvals via Gatekeeper
During `Gatekeeper#authorize_danger`:
1. If the tool supports session approvals, include the tool's custom choice label mapped to the symbol `:session` in the prompt select options.
2. If the user selects `:session`:
   - `Norn::Mode#execute_tool` appends the approval pattern to the active session:
     `session.append(:session_approvals, tool.session_approval_pattern(args))`
   - Prints `"🔓 Action authorized."` and proceeds to tool execution.

---

## 4. Security & Validation Boundaries

1. **Safety Enclosure**: Dangerous parameters or commands are never auto-approved. `dangerous?(args)` serves as a static boundary, ensuring that even if the session is whitelisted for `git`, executing `git push` or `git reset --hard` will bypass the session cache and force explicit user interaction.
2. **Pre-Seeded Autonomous Execution**: Because session approvals are stored in `Norn::Session`, an automated runner or test harness can pre-populate the session with approvals (e.g. `{ tool_name: "git" }`) to execute safe commands autonomously without blocking or throwing TTY errors.

---

## 5. Testing & Verification Plan

1. **Unit Specs (`spec/norn/session_spec.rb`)**:
   - Verify that `Norn::Session` initializes with empty `:session_approvals`.
   - Verify that helper methods safely retrieve and store approvals.
2. **Integration Specs (`spec/norn/session_approvals_spec.rb`)**:
   - Mock a `DummyMode` and `DummyTool`.
   - Verify that whitelisting a tool auto-approves safe executions.
   - Verify that dangerous executions of the same tool are NOT auto-approved and trigger prompts.
   - Verify the custom `GitTool` integration specifically.
