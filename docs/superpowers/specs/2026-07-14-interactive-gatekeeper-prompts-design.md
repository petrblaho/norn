# Design Spec: Interactive Gatekeeper Prompts and Post-Abort Fallbacks

- **Date**: 2026-07-14
- **Status**: Approved
- **Target Card**: Card 4 (Improve Interactive Approval Prompts with Selection Menus and Post-Abort Fallbacks)

---

## 1. Context & Business Case

Currently, Norn’s gatekeeper uses primitive text-based standard inputs (`gets`) for security capability escalations and danger validation checks. If a user rejects or aborts any proposed change, Norn returns a hard failure which terminates the entire active conversational turn or agent loop.

This produces sub-optimal user experiences:
1. **Prompt Fatigue**: Users must type manual inputs like `y/n` rather than enjoying instantaneous single-key selections.
2. **Brittle Execution**: A single rejected action completely crashes a complex, multi-step agent run, forcing the user to start over rather than letting the agent pivot or try a different approach.

To solve this, we will implement a high-fidelity interactive selection gatekeeper utilizing `TTY::Prompt` alongside a post-abort fallback menu that supports **skipping** executions, **editing** parameters inline via freeform language (leveraging active LLM refinement), or **aborting** the turn cleanly.

---

## 2. Architectural Design & Component Boundaries

We will decouple the user interface and security gatekeeping prompting from the core execution orchestration inside `Norn::Mode` by creating a dedicated UI service.

```
Norn::Mode (Orchestrator)
       │
       ▼
Norn::UI::Gatekeeper (Interface Boundary)
       │
       ├─► TTY::Prompt (Keystroke / Selector Engine)
       │
       └─► LLM Client (Active Provider Refinement)
```

### 2.1 Component: `Norn::UI::Gatekeeper`
- **Location**: `lib/norn/ui/gatekeeper.rb`
- **Responsibility**: Handle all user interactions regarding capability authorization, danger confirmation, file diff rendering, and fallback choice loops.
- **Dependencies**: `tty-prompt` gem, active LLM client, `Norn::DiffHelper` (for color diffs).
- **Initialization**: Takes active input/output streams to allow fully deterministic mocking and testing under RSpec without standard stream pollution.

---

## 3. Detailed Data Flows & Fallback Loop

### 3.1 The Main Execution Loop in `Norn::Mode#execute_tool`
When `execute_tool` is called:
1. Check for missing capabilities. If present and interactive, invoke `Gatekeeper#authorize_capabilities`.
   - If user denies, trigger the **Fallback Choice Loop**.
2. Check for danger guards (e.g., file write/edit). If dangerous and interactive, invoke `Gatekeeper#authorize_danger`.
   - If user denies, trigger the **Fallback Choice Loop**.
3. If authorized, proceed to run the tool block.

### 3.2 The Fallback Choice Loop
If any check is denied, invoke `Gatekeeper#show_fallback_menu`. The menu presents three choices:

#### A. Skip (`:skip`)
- Norn yields a `Success("Tool execution skipped by user request.")`.
- The LLM receives this result, understands the user declined, and continues the conversation or tries a different strategy.

#### B. Edit (`:edit`)
1. Norn prompts the user for freeform feedback: `"Describe the changes you want to make: "`.
2. Send a synthesis prompt to the active LLM client (including the tool description, tool parameters schema, original arguments, and user feedback).
3. If the LLM returns a valid JSON object matching the tool parameters schema:
   - Parse and symbolize parameters to obtain `new_args`.
   - Print `🔧 Modified arguments: #{new_args.inspect}`.
   - Recursively call `execute_tool(tool_name, new_args)`. This routes the modified parameters back through the gatekeeper for capability and danger validation!
4. If LLM synthesis fails or validation fails:
   - Print `❌ Error refining parameters: <error_message>`.
   - Show sub-selection menu:
     - `[t] Try describing changes again` -> Loops back to freeform feedback prompt.
     - `[m] Go back to fallback menu` -> Loops back to fallback menu.

#### C. Abort (`:abort`)
- Returns `Failure(Norn::ToolError.new("Action aborted by user."))` to terminate the active turn cleanly.

---

## 4. Refinement Prompt Specification

To formalize freeform user inputs into valid parameter structures, we will compile the following system instruction to the active LLM client:

```
You are a precise tool parameter refiner. Your task is to update the parameters of a tool based on user feedback.

Tool Name: <tool_name>
Tool Description: <tool_description>
Tool Schema: <tool_json_schema>

Original Parameters: <original_args_json>

User Feedback: <user_feedback>

Analyze the user's feedback, apply requested changes to the original parameters, and ensure they conform to the tool schema.
Output ONLY a raw, valid JSON object containing the updated parameters.
Do NOT wrap output in markdown codeblocks. Do NOT add extra explanation or prose.
```

---

## 5. Security & Validation Boundaries

1. **Re-Gatekeeping Safeguard**: Edited parameters are NEVER trusted or executed directly. They are recursively passed back to `execute_tool`, ensuring they go through capability checks and danger validation (including full diff previews of edited code) before any blocks are run.
2. **Input Sanitization**: Outputs of LLM parameter refinement are stripped of codeblocks (` ```json `), parsed as JSON, and symbolized to preserve consistent key formats throughout the system.
3. **Graceful Failures**: If LLM fails or gets stuck in invalid loops, the user can always break out via the fallback sub-menu and choose to `Abort` or `Skip` manually.

---

## 6. Testing Strategy

1. **Stream Redirection**: Initialize `Norn::UI::Gatekeeper` using isolated `StringIO` readers and writers to test interactive UI menus.
2. **TTY::Prompt Mocking**: Stub interactive choice triggers inside `spec/plugins/slash_commands/` and `spec/norn/mode_gatekeeper_spec.rb` to assert correct option routing.
3. **Mock LLM Parameter Refiner**: Stub active LLM provider calls with mock Success objects to verify recursive argument updating and re-routing.
4. **RSpec Speed and Isolation**: Ensure all tests run green instantly without executing actual external API requests or network calls.
