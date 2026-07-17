# RTK Rewrite Pluggable Plugin Design Spec

This document details the architecture and implementation of the **RTK Pluggable Plugin** for Norn. This plugin intercepts system command execution and rewrites commands via `rtk rewrite <command>` to utilize optimized, token-saving `rtk` commands as the single source of truth.

---

## 1. Requirements & Objectives

- **Delegated Rewrite Logic:** All command rewrite logic is delegated to the external `rtk rewrite` binary. The Norn plugin serves as a thin wrapper.
- **Boot-Time Presence Detection:** The plugin checks for the `rtk` executable on initialization. If it is missing, it displays a warning and completely disables itself.
- **Dynamic Hook Exclusion:** If `rtk` is missing or disabled at boot-time, the plugin must not register itself for the `:before_subprocess_execute` hook. It overrides `respond_to?` and `respond_to_missing?` so Norn's `PluginManager` completely bypasses registering it as a middleware subscriber.
- **Configuration & Validation:** Adds schema-validated configurations to `Norn::Config` with defaults:
  - `rtk_enabled` (bool, default: `true`)
  - `rtk_warn_if_missing` (bool, default: `true`)
  - `rtk_path` (string, default: `nil`)

---

## 2. Component Design & Changes

### A. Core Configurations
We will register three new settings in `lib/norn/config.rb` and validate them in `lib/norn/config_loader.rb` via `dry-schema`:

```ruby
# In lib/norn/config.rb:
setting :rtk_enabled, default: true
setting :rtk_warn_if_missing, default: true
setting :rtk_path, default: nil

# In lib/norn/config_loader.rb:
optional(:rtk_enabled).maybe(:bool)
optional(:rtk_warn_if_missing).maybe(:bool)
optional(:rtk_path).maybe(:string)
```

### B. RTK Plugin (`plugins/rtk/plugin.rb`)
- Inherits from `Norn::Plugin` and overrides `self.plugin_name` to return `"rtk"`.
- Performs a robust search of `ENV['PATH']` (or `rtk_path` if provided) to locate the `rtk` binary on boot.
- Overrides `respond_to?` and `respond_to_missing?` to conditionally exclude the `:before_subprocess_execute` hook if `rtk` is missing or disabled.
- Executes `rtk rewrite <command>` using `Open3.capture3`.
- Replaces the payload command if the rewritten output is non-empty and different.

---

## 3. Data Flow

```
LLM / Tool Execute
        │
        ▼
execute_command(command)
        │
        ▼
PluginManager.trigger_middleware(:before_subprocess_execute, payload)
        │
        ├─► RtkPlugin.respond_to?(:before_subprocess_execute) ──(No / Missing rtk)─► Skip RtkPlugin
        │
        └─► (Yes) ──► rtk rewrite <command>
                          │
                          ├─► success & mutated output ──► Update payload command
                          └─► failure / same output ─────► Return original payload
```

---

## 4. Testing Strategy

Create a unit/integration test suite at `spec/plugins/rtk/plugin_spec.rb` to cover:
1. **Dependency Detection:** Verifies it correctly detects `rtk` binary presence inside `PATH` or custom `rtk_path`.
2. **Warn on Missing:** Verifies warning `[rtk] rtk binary not found in PATH — plugin disabled` is emitted when missing and configured to warn.
3. **Suppressed Warning:** Verifies no warning is printed when `rtk_warn_if_missing` is false.
4. **Dynamic Hooks Exclusion:** Asserts that `respond_to?(:before_subprocess_execute)` evaluates to `false` if `rtk` is disabled or missing.
5. **Command Rewriting:** Mocks `Open3.capture3` to simulate successful command rewriting, asserting that commands are replaced correctly.
6. **Error Pass-through:** Verifies execution failures inside `rtk rewrite` allow the original command to pass through untouched.
