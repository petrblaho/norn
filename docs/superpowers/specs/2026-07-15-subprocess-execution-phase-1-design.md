# Design Spec: Subprocess Execution - Phase 1: The Local Muscle (sys:execute)

- **Date**: 2026-07-15
- **Status**: Approved
- **Target Card**: Card 25 (Subprocess Execution - Phase 1: The Local Muscle (sys:execute))

---

## 1. Context & Business Case

The Norn codebase defines a high-risk `:sys_execute` capability, but currently lacks any tool that actually executes local commands. This prevents agents from running compilers, running tests, or performing standard CLI file/system work directly.

In Phase 1 of our subprocess execution roadmap, we will build a secure, robust, and highly composable `execute_command` tool. 

To future-proof the architecture for subsequent phases and deeply nested agent environments, we will implement a **Fractal Composite Execution Pattern**. Under this design, there is no technical difference between a subprocess, a subagent, a parent agent, or the main application. Every execution node in the tree behaves as a uniform, composable entity that gathers results, streams them one-way, and propagates standard monadic outcomes.

---

## 2. Fractal Architectural Design & Component Boundaries

We model Norn's execution topology as a **Fractal Composite Tree** where every execution node is technically uniform but has distinct parent bindings:

```
                  ┌──────────────────────────┐
                  │    Host Terminal / OS    │  ◄── [Host Level]
                  └─────────────┬────────────┘
                                │ (POSIX Exit Code / pipes)
                                ▼
                  ┌──────────────────────────┐
                  │   Root Node (Norn CLI)   │  ◄── [Norn Supervisor]
                  └─────────────┬────────────┘
                                │ (monadic dispatch)
                                ▼
                  ┌──────────────────────────┐
                  │ Agent Node (Task Mode)   │  ◄── [Branch: Coordinator]
                  └─────────────┬────────────┘
                                │ (monadic dispatch)
                                ▼
                  ┌──────────────────────────┐
                  │  Agent Node (Code Mode)  │  ◄── [Branch: Worker]
                  └─────────────┬────────────┘
                                │ (monadic dispatch)
                                ▼
                  ┌──────────────────────────┐
                  │  Subprocess Node (Leaf)  │  ◄── [Leaf: OS Process]
                  └──────────────────────────┘
```

### 2.1 The Uniform Interface Contract

To enable perfect, infinite nesting, every node in the execution tree complies with the exact same interface and returns the exact same monadic type wrapping a unified **`Outcome`**:

* **Success(Outcome)**: The execution node successfully completed its task. Results are stored in `Outcome.stdout`.
* **Failure(Outcome)**: The execution node encountered a failure or errored out. Error diagnostics are stored in `Outcome.stderr`.

#### The Uniform `Outcome` Schema
```ruby
module Norn
  module Execution
    class Outcome
      attr_reader :stdout, :stderr, :exit_code

      def initialize(stdout: "", stderr: "", exit_code: 0)
        @stdout = stdout.to_s
        @stderr = stderr.to_s
        @exit_code = exit_code.to_i
      end

      def success?
        @exit_code == 0
      end

      def failure?
        !success?
      end

      # Monoid addition algebra: merges two sequential outputs together one-way
      def +(other)
        self.class.new(
          stdout: [@stdout, other.stdout].reject(&:empty?).join("\n"),
          stderr: [@stderr, other.stderr].reject(&:empty?).join("\n"),
          # If either node failed, the combined execution has failed (returns max code)
          exit_code: [self.exit_code, other.exit_code].max
        )
      end

      # Formats output cleanly for LLM / User console consumption
      def to_s
        if success?
          stdout
        else
          "Execution Failed (exit code #{exit_code}):\n#{stderr}\n#{stdout}"
        end
      end
    end
  end
end
```

---

## 3. Concurrency & Stream Processing Design

Because OS pipes have limited buffer sizes (64KB on Linux), reading standard output and standard error sequentially can lead to deadlocks where the child process blocks waiting for a buffer to clear while the parent is waiting for a different stream. 

We will use **standard, lightweight Ruby Threads** to read from `stdout` and `stderr` concurrently and safely inside `SubprocessRunner`.

### 3.1 Streaming and Drainage Flow

```
              ┌──────────────────────────┐
              │     SubprocessRunner     │
              └─────────────┬────────────┘
                            │ (Open3.popen3)
             ┌──────────────┴──────────────┐
             ▼                             ▼
     [Thread 1: stdout]            [Thread 2: stderr]
   - Non-blocking chunk read     - Non-blocking chunk read
   - Yield to callback stream    - Yield to callback stream
             │                             │
             └──────────────┬──────────────┘
                            ▼
              ┌──────────────────────────┐
              │     Callback Block       │
              └─────────────┬────────────┘
                            ├─► Live Console Print (red for stderr)
                            └─► Collect in-memory Outcome
```

#### The `SubprocessRunner` Execution Engine:
```ruby
require "open3"

module Norn
  module UI
    class SubprocessRunner
      def self.run(command, workspace_root: Norn.workspace_root)
        accumulated_stdout = ""
        accumulated_stderr = ""

        Open3.popen3(command, chdir: workspace_root) do |stdin, stdout, stderr, wait_thr|
          stdin.close # Non-interactive execution

          stdout_thread = Thread.new do
            begin
              while (chunk = stdout.readpartial(4096))
                accumulated_stdout << chunk
                yield :stdout, chunk if block_given?
              end
            rescue EOFError
              # Stream ended
            end
          end

          stderr_thread = Thread.new do
            begin
              while (chunk = stderr.readpartial(4096))
                accumulated_stderr << chunk
                yield :stderr, chunk if block_given?
              end
            rescue EOFError
              # Stream ended
            end
          end

          stdout_thread.join
          stderr_thread.join
          
          exit_code = wait_thr.value.exitstatus
          
          Norn::Execution::Outcome.new(
            stdout: accumulated_stdout,
            stderr: accumulated_stderr,
            exit_code: exit_code
          )
        end
      rescue Errno::ENOENT => e
        # Handle command-not-found system error
        Norn::Execution::Outcome.new(
          stderr: "Failed to spawn process: command not found - #{e.message}",
          exit_code: 127
        )
      end
    end
  end
end
```

---

## 4. Security & Gatekeeping Boundaries

Because subprocess execution has highest potential risk, we implement three explicit layers of validation:

### 4.1 Static Danger Classification
* The tool is declared as `dangerous: true`. Under Norn's `Gatekeeper`, this **statically bypasses session-level auto-approvals** by default. Each command will always trigger a prompt, ensuring the agent cannot sneak in unauthorized system commands under previous approvals.

### 5.2 Catastrophic Regex Validation (`Norn::Plugins::SubprocessTools::CommandValidator`)
Before execution, commands are passed through a strict security blacklist to prevent catastrophic data loss or elevation:

```ruby
module Norn
  module Plugins
    module SubprocessTools
      class CommandValidator
        BLACKLIST = [
          /\bsudo\b/i,                       # Prevent root privilege escalations
          /rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\//,  # Block rm -rf /
          /rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\*/,  # Block rm -rf *
          /rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\./,  # Block rm -rf . (current dir wipe)
          />\s*\/dev\/(?:sda|sdb|nvme)/,     # Block direct disk writes
          /\bdd\b.*if=.*of=\/dev\//          # Block partition formatting
        ].freeze

        def self.validate!(command)
          BLACKLIST.each do |pattern|
            if command =~ pattern
              raise SecurityError, "Execution Blocked: Command matched a blacklisted destructive pattern!"
            end
          end
        end
      end
    end
  end
end
```

---

## 5. Testing Strategy & Verification Plan

We will enforce strict test coverage to guarantee system safety and performance:

1. **`spec/plugins/subprocess_tools/command_validator_spec.rb`**
   * Assert that safe tools (`git status`, `bundle exec rspec`) pass.
   * Assert that unsafe patterns (`rm -rf /`, `sudo apt install`) raise `SecurityError`.
2. **`spec/norn/ui/subprocess_runner_spec.rb`**
   * Assert real-time stream chunk yielding for both `:stdout` and `:stderr`.
   * Verify monoid addition (`+`) algebra for combining outcomes.
   * Verify correct handling of `Errno::ENOENT` to return a `127` exit status with stderr warning.
3. **`spec/plugins/subprocess_tools/plugin_spec.rb`**
   * Verify dynamic integration, capability checks (`:sys_execute`), and gatekeeper triggers.
