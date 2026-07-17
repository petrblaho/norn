# Design Spec: Unified Subprocess Execution & Composable Hook Network

* **Date**: 2026-07-16
* **Status**: Approved
* **Authors**: Petr Blaho & Norn AI
* **Target Card**: [Unified Subprocess Execution & Composable Hook Network]

---

## 1. Context & Problem Statement

Currently, Norn features two disconnected pathways for subprocess execution:
1. **The Hook-Enabled, Stateful Pathway:** The `execute_command` tool (provided by `SubprocessToolsPlugin`) runs commands in a state-preserving persistent shell (`Norn::Execution::Subshell`). It triggers the `:before_subprocess_execute` middleware hook, along with real-time streaming output (`:on_subprocess_output`) and post-execution (`:after_subprocess_execute`) hooks.
2. **The Hook-Bypassing, Stateless Pathway:** The `git` (provided by `GitPlugin`) and `rspec` (provided by `RSpecPlugin`) tools execute commands using isolated `Open3.capture3` calls with argument arrays.

While array-based execution is secure, this division limits **plugin composability**:
* **No Interception/Rewriting:** Dynamic rewrite plugins, such as the `rtk` plugin, cannot intercept or optimize `git` or `rspec` commands.
* **Loss of Working Directory State:** Running `cd some_dir/` in the persistent subshell does not affect subsequent `git` or `rspec` actions, as they run statelessly at the workspace root.
* **No Real-Time Progress Streaming:** Other plugins (e.g., real-time UI stream managers) do not receive streaming stdout/stderr chunks for `git` or `rspec` operations.

---

## 2. Architecture & Safe Shell Delegation

To solve the composability and state synchronization problems, we will unify execution on the stateful, hook-enabled pathway. 

```
       [GitPlugin / RSpecPlugin]
                  │
                  ▼ (Compiles arguments securely)
          Shellwords.join(cmd)
                  │
                  ▼ (Triggers middleware)
    :before_subprocess_execute hook (rtk plugin intercepts/rewrites here)
                  │
                  ▼ (Decides execution path)
       Is "subprocess.shell" container registered?
       ├──► YES ──► Norn::Container["subprocess.shell"].execute(rewritten_cmd)
       │              (Preserves environment, prints real-time stream via :on_subprocess_output)
       └──► NO  ──► Open3.capture3(rewritten_cmd)
                      (Fallback for isolated unit tests / bootstrap phases)
```

### 2.1 Security & Shell Injection Prevention
To maintain absolute security against shell injection vulnerabilities, we will compile the structured array arguments of both `git` and `rspec` using Ruby's standard `Shellwords.join` utility. This ensures any injected metacharacters (e.g. `;`, `|`, `&`) are safely escaped before passing to the shell.

### 2.2 Unified Streaming & Event Hooks
When delegating to the state-preserving persistent subshell, the execution block will yield stream chunks in real-time. This ensures:
1. The `:on_subprocess_output` notification hook is triggered for all stdout/stderr chunks.
2. Real-time stderr chunks are formatted with standard terminal colors (e.g., red) and printed directly to the output context.

---

## 3. Component Details & Refactoring

### 3.1 Refactoring `GitPlugin` (`plugins/git/plugin.rb`)
The `git` tool execution block will be updated as follows:
* Construct the command array: `cmd = ["git", subcmd] + extra_args`.
* Escape into a safe shell command string: `command_str = Shellwords.join(cmd)`.
* Fire the `:before_subprocess_execute` hook:
  ```ruby
  payload = { command: command_str }
  before_result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
  sanitized_command = before_result.success? ? before_result.value![:command] : command_str
  ```
* Execute via the `"subprocess.shell"` container if available, falling back to `Open3.capture3` if not.
* Stream stdout/stderr chunks and format stderr as red if executed via the subshell.

### 3.2 Refactoring `RSpecPlugin` (`plugins/rspec/plugin.rb`)
The `rspec` tool execution block will be updated to match the exact same pipeline:
* Compile path, line numbers, and arguments using `Shellwords.join(cmd)`.
* Trigger `:before_subprocess_execute` middleware hook.
* Delegate to `"subprocess.shell"` if available, streaming stdout/stderr in real-time, and fall back to `Open3.capture3` if not.

---

## 4. Testing & Verification Plan

### 4.1 Unit Test Backward Compatibility
Existing tests in `spec/plugins/git/plugin_spec.rb` and `spec/plugins/rspec/plugin_spec.rb` mock `Open3.capture3`. Because the refactored code falls back gracefully to `Open3.capture3` when the `"subprocess.shell"` container is unregistered, existing tests will pass seamlessly.

### 4.2 Integration Verification
We will add new tests to verify:
1. **Hook Invocation:** Verify that calling the `git` and `rspec` tools triggers `:before_subprocess_execute` middleware hooks.
2. **Command Interception:** Verify that if the hook modifies the command (e.g. via mock or `rtk` plugin), the modified/rewritten command is the one actually executed.
3. **Environment/Directory Stateful Preservation:** Verify that directory changes made via `cd` in `execute_command` are preserved when calling `git` or `rspec` tools.
