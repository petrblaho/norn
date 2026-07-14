# Design Spec: Tool-Level Danger Override for Statically Dangerous Tools

- **Date**: 2026-07-14
- **Status**: Proposed
- **Target**: Allow users to session-approve statically dangerous tools (like `file_write` and `file_edit`) in interactive mode, bypassing subsequent prompts.

---

## 1. Context & Business Case

Currently, safe tools with safe subcommands (like `git status`) can be session-approved to eliminate prompt fatigue in interactive pairing modes. However, statically dangerous tools (like `file_write` or `file_edit`) always prompt the user even if approved for the session.

This occurs because `Norn::Tool#session_approved?` enforces a static boundary:
```ruby
has_approval && !dangerous?(args)
```
For statically dangerous tools, `dangerous?(args)` is always `true`. Thus, `session_approved?` always returns `false`. This creates a UX defect where the user is offered `"⚡ Approve '<tool>' for the rest of this session"`, but selecting it still prompts them on every subsequent execution.

To fix this and allow the user to approve dangerous tools for the session, we will implement a tool-level override that permits statically dangerous tools to bypass prompts if the user explicitly approved them.

---

## 2. Architectural Design

We introduce `allow_session_danger?` on `Norn::Tool` to let each tool declare whether it allows session-level approvals to bypass its danger checks.

```
                  Norn::Mode (Orchestrator)
                         │
                         ├─► Norn["session"] (Read approvals)
                         ▼
               Norn::Tool (API Contract)
                         │
         ┌───────────────┴───────────────┐
         ▼                               ▼
    Base Tool Class                   GitTool
- session_approved?                - dangerous?(args)
- allow_session_danger?            - allow_session_danger? (returns false)
  (returns @dangerous)
```

### 2.1 The Tool Contract Changes (`Norn::Tool`)

We update `Norn::Tool` with:
1. `allow_session_danger?`: Defaults to `@dangerous`. If a tool is statically designated as dangerous (like `file_write`), this returns `true`.
2. `session_approved?(session, args)`: Updated to check if either the action is safe, OR the tool allows session-level danger bypass:
   ```ruby
   def session_approved?(session, args)
     return false if session.nil?
     
     approvals = session.get(:session_approvals) || []
     has_approval = approvals.any? { |app| app[:tool_name] == name }
     
     has_approval && (!dangerous?(args) || allow_session_danger?)
   end
   ```

### 2.2 Specialize `GitTool`

`GitTool` represents a tool with dynamic danger (some safe subcommands, some dangerous ones). We want safe subcommands to bypass but dangerous ones (`commit`, `push`) to **always** prompt.
We override `allow_session_danger?` on `GitTool` to explicitly return `false`:
```ruby
def allow_session_danger?
  false
end
```

This preserves the secure guardrails for Git, ensuring that dangerous operations like `git push` still prompt, while allowing safe subcommands like `git status` to bypass.

---

## 3. Testing & Verification Plan

1. **Unit Specs (`spec/norn/tool_spec.rb`)**:
   - Verify `Norn::Tool#allow_session_danger?` returns `true` for statically dangerous tools and `false` for others.
   - Verify `session_approved?` returns `true` for statically dangerous tools if they have been approved in the session.
2. **Integration Specs (`spec/plugins/git/plugin_spec.rb`)**:
   - Verify `GitTool#allow_session_danger?` returns `false`.
   - Verify that even if `git` is session-approved, a dangerous subcommand (like `push`) still returns `false` on `session_approved?` and prompts.
3. **End-to-End/Integration (`spec/norn/session_approvals_spec.rb`)**:
   - Verify that whitelisting a statically dangerous tool bypasses subsequent execution prompts.
