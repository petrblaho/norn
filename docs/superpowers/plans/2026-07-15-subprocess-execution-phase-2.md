# Subprocess Execution - Phase 2: The Hook Network (Persistent Shell & Events) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a long-lived, stateful background subshell execution engine for Norn that keeps directories and environment variables active across tool runs, while streaming raw real-time execution hooks.

**Architecture:** We will build a unified `Norn::Execution::Subshell` process wrapper that spawns `/bin/bash` once. It multiplexes stdout/stderr dynamically via standard `IO.select` reads. To safely detect process termination and command completion without blocking, we inject unique randomized sentinel tokens (`NORN_SENTINEL_<uuid>`) and capture execution outcomes deterministically.

**Tech Stack:** Pure Ruby, standard libraries (`open3`, `securerandom`, `thread`), RSpec.

## Global Constraints

* Keep implementations DRY, YAGNI, and TDD-driven.
* Follow conventional commit guidelines with atomic, step-by-step commits.
* All streams and file writes must handle binary/malformed characters safely via forced UTF-8 sanitization.
* Ensure all RSpec unit and integration tests run green instantly without external network calls.

---

## File Structure

Before writing code, we map out the specific file layout:
1. `lib/norn/plugin_manager.rb` — Declare new subshell execution hooks.
2. `lib/norn/execution/subshell.rb` — Persistent subshell engine with multiplexed `IO.select` and sentinel parsing.
3. `plugins/subprocess_tools/plugin.rb` — Refactored `execute_command` tool routing commands through the new subshell and triggering hooks.

---

### Task 1: Declare Subprocess Execution Event Hooks

**Files:**
- Modify: `lib/norn/plugin_manager.rb`
- Test: Run existing test suite to ensure no regressions.

**Interfaces:**
- Produces: Registration of `:before_subprocess_execute`, `:on_subprocess_output`, and `:after_subprocess_execute` in `Norn::PluginManager`.

- [ ] **Step 1: Declare the new hooks in Norn's core hooks registry**

Modify `lib/norn/plugin_manager.rb` at line 164 to register our three new hooks:
```ruby
# In lib/norn/plugin_manager.rb
      def register_core_hooks!
        declare_hook :on_boot, desc: "Fires when Norn finishes loading dependencies."
        declare_hook :on_tool_register, desc: "Fires to populate the global ToolRegistry."
        declare_hook :on_cli_register, desc: "Fires to let plugins register custom CLI commands."
        declare_hook :on_mode_register, desc: "Fires to register custom execution modes."
        declare_hook :on_slash_commands_register, desc: "Fires to let plugins register custom slash commands."
        declare_hook :on_user_input, desc: "ROP middleware. Intercepts and processes raw user input before execution."
        declare_hook :before_llm_call, desc: "Fires before calling LLM. Allows inspecting/mutating messages."
        declare_hook :after_llm_call, desc: "Fires after LLM call completes. Informational."
        declare_hook :on_render_response, desc: "ROP middleware. Formats/renders response text in-place."
        declare_hook :after_tool_call, desc: "Fires after a tool execution completes. Informational."
        declare_hook :after_llm_response, desc: "Fires when an LLM response with metadata is received. Informational."
        
        # New subprocess hooks
        declare_hook :before_subprocess_execute, desc: "ROP middleware. Allows inspection/auditing of a shell command."
        declare_hook :on_subprocess_output, desc: "Notification. Emits a chunk of stdout/stderr read in real-time."
        declare_hook :after_subprocess_execute, desc: "Notification. Reports outcome and duration of a command."
      end
```

- [ ] **Step 2: Run all RSpec tests to ensure no core regressions**

Run: `bundle exec rspec spec/norn/plugin_manager_spec.rb`
Expected: ALL PASS

- [ ] **Step 3: Commit the hook declarations**

Run:
```bash
git add lib/norn/plugin_manager.rb
git commit -m "feat(subprocess): declare subprocess lifecycle hooks in plugin manager"
```

---

### Task 2: Implement `Norn::Execution::Subshell`

**Files:**
- Create: `lib/norn/execution/subshell.rb`
- Test: `spec/norn/execution/subshell_spec.rb`

**Interfaces:**
- Produces: `Norn::Execution::Subshell` class exposing:
  * `#start` (lazy-loaded process spawner)
  * `#execute(command) { |stream_type, chunk| ... }` (returns `Norn::Execution::Outcome`)
  * `#stop` (graceful termination of background shell)
  * `#started?` (status indicator)

- [ ] **Step 1: Write the failing unit tests for stateful persistence and streaming**

Create the spec file `spec/norn/execution/subshell_spec.rb`:
```ruby
require "spec_helper"
require "norn/execution/subshell"
require "norn/execution/outcome"

RSpec.describe Norn::Execution::Subshell do
  subject(:subshell) { described_class.new }

  after do
    subshell.stop if subshell.started?
  end

  it "lazily starts the background process" do
    expect(subshell.started?).to be false
    subshell.start
    expect(subshell.started?).to be true
  end

  it "preserves directory changes across consecutive commands" do
    subshell.start
    subshell.execute("cd lib")
    outcome = subshell.execute("pwd")
    expect(outcome.stdout).to include("lib")
  end

  it "retains exported environment variables" do
    subshell.start
    subshell.execute("export NORN_TEST_ENV=jester")
    outcome = subshell.execute("echo $NORN_TEST_ENV")
    expect(outcome.stdout.strip).to eq("jester")
  end

  it "streams stdout chunks in real-time" do
    subshell.start
    chunks = []
    subshell.execute("echo 'hello world'") do |type, chunk|
      chunks << [type, chunk] if type == :stdout
    end
    expect(chunks.flatten.join).to include("hello world")
  end
end
```

- [ ] **Step 2: Run the test suite and verify it fails**

Run: `bundle exec rspec spec/norn/execution/subshell_spec.rb`
Expected: FAIL with "NameError: uninitialized constant Norn::Execution::Subshell"

- [ ] **Step 3: Implement the `Norn::Execution::Subshell` engine**

Create `lib/norn/execution/subshell.rb`:
```ruby
require "open3"
require "securerandom"
require "thread"

module Norn
  module Execution
    class Subshell
      def initialize(workspace_root: Norn.workspace_root)
        @workspace_root = workspace_root
        @lock = Mutex.new
        @started = false
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thr = nil
      end

      def started?
        @started
      end

      def start
        @lock.synchronize do
          return if @started

          shell_exec = ENV["SHELL"] || "bash"
          # Detect available shell
          unless system("which #{shell_exec} >/dev/null 2>&1")
            shell_exec = "sh"
          end

          # Spawn persistent subshell process non-blockingly
          @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(shell_exec, chdir: @workspace_root)
          @started = true
        end
      end

      def execute(command, timeout: 60)
        start unless started?

        @lock.synchronize do
          token = "NORN_SENTINEL_#{SecureRandom.hex(8)}"
          out_sentinel = "#{token}_OUT"
          err_sentinel = "#{token}_ERR"

          # Write command followed by unique sentinels to stdout and stderr
          @stdin.puts(command)
          @stdin.puts("echo \"\"") # handle commands without training newline
          @stdin.puts("echo \"#{out_sentinel} $?\"")
          @stdin.puts("echo \"#{err_sentinel}\" >&2")

          accumulated_stdout = ""
          accumulated_stderr = ""
          stdout_done = false
          stderr_done = false
          exit_code = 0

          loop do
            break if stdout_done && stderr_done

            # Dynamic multiplexing with standard timeout
            ready = IO.select([@stdout, @stderr], nil, nil, timeout)
            if ready.nil?
              raise Timeout::Error, "Command execution timed out after #{timeout} seconds"
            end

            ready[0].each do |stream|
              if stream == @stdout
                begin
                  chunk = @stdout.read_nonblock(4096)
                  accumulated_stdout << chunk

                  if accumulated_stdout.include?(out_sentinel)
                    if match = accumulated_stdout.match(/#{out_sentinel}\s+(\d+)/)
                      exit_code = match[1].to_i
                      stdout_done = true
                    end
                  end

                  yield :stdout, chunk if block_given?
                rescue IO::WaitReadable
                  # No bytes available immediately, wait next select
                rescue EOFError
                  stdout_done = true
                end
              elsif stream == @stderr
                begin
                  chunk = @stderr.read_nonblock(4096)
                  accumulated_stderr << chunk

                  if accumulated_stderr.include?(err_sentinel)
                    stderr_done = true
                  end

                  yield :stderr, chunk if block_given?
                rescue IO::WaitReadable
                rescue EOFError
                  stderr_done = true
                end
              end
            end
          end

          # Clean up the output by stripping off sentinel tokens
          clean_stdout = accumulated_stdout.gsub(/\n?#{out_sentinel}\s+\d+\n?/, "").strip
          clean_stderr = accumulated_stderr.gsub(/\n?#{err_sentinel}\n?/, "").strip

          Norn::Execution::Outcome.new(
            stdout: clean_stdout,
            stderr: clean_stderr,
            exit_code: exit_code
          )
        end
      rescue EOFError, Errno::EPIPE
        # If the background process terminated suddenly, reset state
        stop
        Norn::Execution::Outcome.new(
          stderr: "Persistent subshell terminated abruptly.",
          exit_code: 1
        )
      end

      def stop
        @lock.synchronize do
          return unless @started
          
          begin
            @stdin.puts("exit") if @stdin && !@stdin.closed?
            Process.kill("TERM", @wait_thr.pid) if @wait_thr && @wait_thr.alive?
          rescue
            # Ignore exit command writing or pid signaling issues
          ensure
            @stdin.close if @stdin && !@stdin.closed?
            @stdout.close if @stdout && !@stdout.closed?
            @stderr.close if @stderr && !@stderr.closed?
            @started = false
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the specs and confirm they pass**

Run: `bundle exec rspec spec/norn/execution/subshell_spec.rb`
Expected: ALL PASS (4 green examples)

- [ ] **Step 5: Commit the Subshell engine**

Run:
```bash
git add lib/norn/execution/subshell.rb spec/norn/execution/subshell_spec.rb
git commit -m "feat(subprocess): implement persistent Subshell engine with IO.select and sentinel tokens"
```

---

### Task 3: Refactor SubprocessToolsPlugin and Wire Hooks

**Files:**
- Modify: `plugins/subprocess_tools/plugin.rb`
- Test: `spec/plugins/subprocess_tools/plugin_spec.rb`

**Interfaces:**
- Consumes: `Norn::Execution::Subshell` from Container `"subprocess.shell"`
- Produces: Integrated `execute_command` tool utilizing persistent shell execution and triggering the complete Hook Network.

- [ ] **Step 1: Write tool integration and hook trigger tests**

Modify `spec/plugins/subprocess_tools/plugin_spec.rb` to cover the new persistent subshell wiring, custom environment state persistence, and real-time execution hooks:
```ruby
require "spec_helper"
require "norn/plugin_manager"
require "norn/tool_registry"
require_relative "../../../plugins/subprocess_tools/plugin"

RSpec.describe SubprocessToolsPlugin do
  let(:container) { Norn::Container }
  let(:registry) { Norn::ToolRegistry }

  before do
    Norn::PluginManager.reset!
    Norn::PluginManager.register_core_hooks!
    
    # Setup test double for subshell
    @subshell = Norn::Execution::Subshell.new
    container.stub("subprocess.shell", @subshell) do
      plugin = described_class.new
      plugin.on_boot(container)
      plugin.on_tool_register(registry)
    end
  end

  after do
    @subshell.stop if @subshell.started?
  end

  it "registers the execute_command tool" do
    expect(registry.resolve("execute_command")).not_to be_nil
  end

  it "retains environment and directory states across tool runs" do
    container.stub("subprocess.shell", @subshell) do
      tool = registry.resolve("execute_command")
      
      # Shift directories in turn 1
      tool.call({ command: "cd lib" }, nil)
      
      # Check directory in turn 2
      outcome = tool.call({ command: "pwd" }, nil)
      expect(outcome).to include("lib")
    end
  end

  it "emits real-time progress events over :on_subprocess_output hook" do
    container.stub("subprocess.shell", @subshell) do
      tool = registry.resolve("execute_command")
      emitted_events = []

      Norn::PluginManager.subscribe(:on_subprocess_output) do |payload|
        emitted_events << payload
      end

      tool.call({ command: "echo 'trigger hook'" }, nil)
      expect(emitted_events.any? { |e| e[:chunk].include?("trigger hook") }).to be true
    end
  end
end
```

- [ ] **Step 2: Run the test suite and verify it fails**

Run: `bundle exec rspec spec/plugins/subprocess_tools/plugin_spec.rb`
Expected: FAIL due to stateless Open3 routing and lack of hooks inside original plugin code.

- [ ] **Step 3: Implement persistent routing and hook triggering inside SubprocessToolsPlugin**

Rewrite `plugins/subprocess_tools/plugin.rb` to route through the persistent shell and trigger execution events:
```ruby
require "dry/monads"

class SubprocessToolsPlugin < Norn::Plugin
  include Dry::Monads[:result]

  def self.plugin_name
    "subprocess_tools"
  end

  SUBPROCESS_SCHEMA = {
    type: "object",
    properties: {
      command: {
        type: "string",
        description: "The raw shell command string to execute in the workspace root."
      }
    },
    required: ["command"]
  }

  def on_boot(container)
    require_relative "../../lib/norn/execution/subshell"
    
    unless container.key?("subprocess.shell")
      container.register("subprocess.shell") do
        Norn::Execution::Subshell.new
      end
    end
  end

  def on_tool_register(registry)
    execute_command_tool = Norn::Tool.new(
      "execute_command",
      "Executes raw shell or command-line instructions safely in the project workspace root.",
      SUBPROCESS_SCHEMA,
      required_capabilities: [:sys_execute],
      system_instructions: "Use this tool to run workspace-local processes, tests, compiles, or checkups.",
      dangerous: true
    ) do |args, context|
      command = args[:command].to_s.strip
      
      # 1. Run security validator on command
      Norn::Execution::CommandValidator.validate!(command)

      # 2. Trigger the before_subprocess_execute middleware hook
      payload = { command: command }
      before_result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
      
      if before_result.failure?
        next "Subprocess execution aborted: #{before_result.failure.message}"
      end
      
      sanitized_command = before_result.value![:command]

      # 3. Retrieve output streams
      output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout
      subshell = Norn::Container["subprocess.shell"]

      # 4. Record execution duration
      start_time = Time.now

      # 5. Execute process over state-preserving persistent shell
      outcome = subshell.execute(sanitized_command) do |stream_type, chunk|
        # Emit raw byte chunks to standard output notifications hook in real-time
        Norn::PluginManager.trigger_notification(:on_subprocess_output, {
          stream: stream_type,
          chunk: chunk
        })

        if stream_type == :stderr
          output_stream.print "\e[1;31m#{chunk}\e[0m"
        else
          output_stream.print chunk
        end
      end

      duration = Time.now - start_time

      # 6. Trigger the after_subprocess_execute notification hook
      Norn::PluginManager.trigger_notification(:after_subprocess_execute, {
        command: sanitized_command,
        exit_code: outcome.exit_code,
        duration: duration
      })

      # Return Outcome
      outcome.to_s
    end

    registry.register(execute_command_tool)
  end
end
```

- [ ] **Step 4: Run the specs and confirm they pass**

Run: `bundle exec rspec spec/plugins/subprocess_tools/plugin_spec.rb`
Expected: ALL PASS

- [ ] **Step 5: Run the entire test suite to guarantee 100% green compliance**

Run: `bundle exec rspec`
Expected: ALL PASS

- [ ] **Step 6: Commit the plugin refactoring**

Run:
```bash
git add plugins/subprocess_tools/plugin.rb spec/plugins/subprocess_tools/plugin_spec.rb
git commit -m "feat(subprocess): integrate execute_command with persistent subshell and trigger hooks"
```
