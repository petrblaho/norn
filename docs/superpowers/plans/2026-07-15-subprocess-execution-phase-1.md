# Subprocess Execution - Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a safe, robust, and mathematically composable `execute_command` tool using a Fractal Composite Execution model.

**Architecture:** We will implement a uniform `Execution::Outcome` class mapping to `Success`/`Failure` monads with Monoid addition (`+`) for seamless multi-agent/subprocess outcome aggregation. Spawning is handled non-blockingly via standard Ruby threads reading `Open3.popen3` pipes.

**Tech Stack:** Ruby 3.x, Dry::Monads, Open3, RSpec.

## Global Constraints
* Every node in the execution tree (whether a subprocess, agent, or root) must comply with the same monadic return interface: `Success(Outcome)` or `Failure(Outcome)`.
* Raw terminal command executions must strictly enforce working directory confinement (`chdir: Norn.workspace_root`).
* Blacklisted destructive terminal patterns (such as `rm -rf /`, `sudo`) must raise a `SecurityError` and cause an immediate monadic `Failure` prior to spawning.
* Live console rendering must print stdout and stderr to the screen concurrently, with stderr formatted in warnings/colors.

---

### Task 1: Create `Norn::Execution::Outcome` Domain Model

**Files:**
- Create: `lib/norn/execution/outcome.rb`
- Test: `spec/norn/execution/outcome_spec.rb`

**Interfaces:**
- Consumes: None (Core dependency)
- Produces: `Norn::Execution::Outcome` class exposing:
  * `#initialize(stdout: "", stderr: "", exit_code: 0)`
  * `#stdout` [String], `#stderr` [String], `#exit_code` [Integer]
  * `#success?` [Boolean] (true if exit_code is 0)
  * `#failure?` [Boolean] (true if exit_code is not 0)
  * `#+(other)` [Norn::Execution::Outcome] (Monoid composition)
  * `#to_s` [String] (Human-readable representation)

- [ ] **Step 1: Write the failing unit tests**

Create the spec file `spec/norn/execution/outcome_spec.rb`:
```ruby
require "spec_helper"
require_relative "../../../lib/norn/execution/outcome"

RSpec.describe Norn::Execution::Outcome do
  describe "#success? and #failure?" do
    it "returns true for success? when exit code is 0" do
      outcome = described_class.new(stdout: "ok", exit_code: 0)
      expect(outcome.success?).to be(true)
      expect(outcome.failure?).to be(false)
    end

    it "returns true for failure? when exit code is non-zero" do
      outcome = described_class.new(stderr: "error", exit_code: 1)
      expect(outcome.success?).to be(false)
      expect(outcome.failure?).to be(true)
    end
  end

  describe "#+ (Monoid Addition)" do
    it "merges stdout, stderr, and aggregates the exit code sequentially" do
      out1 = described_class.new(stdout: "step 1", stderr: "", exit_code: 0)
      out2 = described_class.new(stdout: "step 2", stderr: "warning", exit_code: 1)
      
      combined = out1 + out2
      expect(combined.stdout).to eq("step 1\nstep 2")
      expect(combined.stderr).to eq("warning")
      expect(combined.exit_code).to eq(1)
    end
  end

  describe "#to_s" do
    it "returns stdout if successful" do
      outcome = described_class.new(stdout: "good", exit_code: 0)
      expect(outcome.to_s).to eq("good")
    end

    it "returns detailed stderr and stdout if failed" do
      outcome = described_class.new(stdout: "partial", stderr: "bad", exit_code: 2)
      expect(outcome.to_s).to include("Execution Failed (exit code 2):")
      expect(outcome.to_s).to include("bad")
      expect(outcome.to_s).to include("partial")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/execution/outcome_spec.rb`
Expected: FAIL (cannot load such file -- outcome)

- [ ] **Step 3: Write minimal implementation**

Create `lib/norn/execution/outcome.rb`:
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

      def +(other)
        self.class.new(
          stdout: [@stdout, other.stdout].reject(&:empty?).join("\n"),
          stderr: [@stderr, other.stderr].reject(&:empty?).join("\n"),
          exit_code: [self.exit_code, other.exit_code].max
        )
      end

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

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/execution/outcome_spec.rb`
Expected: PASS (all tests green)

- [ ] **Step 5: Require the new file in lib/norn.rb**

Modify: `lib/norn.rb` to require the outcome file. Add near other require statements (e.g. line 22):
```ruby
require_relative "norn/execution/outcome"
```

Run all tests to verify workspace integrity:
`bundle exec rspec`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/norn.rb lib/norn/execution/outcome.rb spec/norn/execution/outcome_spec.rb
git commit -m "feat(subprocess): implement Norn::Execution::Outcome domain model"
```

---

### Task 2: Implement Thread-Safe `Norn::UI::SubprocessRunner`

**Files:**
- Create: `lib/norn/ui/subprocess_runner.rb`
- Test: `spec/norn/ui/subprocess_runner_spec.rb`

**Interfaces:**
- Consumes: `Norn::Execution::Outcome`
- Produces: `Norn::UI::SubprocessRunner` singleton class exposing:
  * `.run(command, workspace_root: Norn.workspace_root) { |type, chunk| ... }` returning `Norn::Execution::Outcome`

- [ ] **Step 1: Write failing runner tests**

Create the spec file `spec/norn/ui/subprocess_runner_spec.rb`:
```ruby
require "spec_helper"
require_relative "../../../lib/norn/ui/subprocess_runner"

RSpec.describe Norn::UI::SubprocessRunner do
  describe ".run" do
    it "runs a successful system command and captures stdout" do
      outcome = described_class.run("echo 'hello world'")
      expect(outcome.success?).to be(true)
      expect(outcome.stdout.strip).to eq("hello world")
      expect(outcome.stderr).to eq("")
    end

    it "runs a failing command and captures stderr and non-zero exit code" do
      outcome = described_class.run("ruby -e 'warn \"my error\"; exit 5'")
      expect(outcome.success?).to be(false)
      expect(outcome.exit_code).to eq(5)
      expect(outcome.stderr.strip).to eq("my error")
    end

    it "yields stdout/stderr chunks in real-time if a block is provided" do
      yielded_chunks = []
      described_class.run("echo 'realtime'") do |stream_type, chunk|
        yielded_chunks << [stream_type, chunk.strip]
      end

      expect(yielded_chunks).to include([:stdout, "realtime"])
    end

    it "handles command not found gracefully and returns exit code 127" do
      outcome = described_class.run("notarealcommandexecuting")
      expect(outcome.success?).to be(false)
      expect(outcome.exit_code).to eq(127)
      expect(outcome.stderr).to include("command not found")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/ui/subprocess_runner_spec.rb`
Expected: FAIL (cannot load such file -- subprocess_runner)

- [ ] **Step 3: Write minimal implementation**

Create `lib/norn/ui/subprocess_runner.rb`:
```ruby
require "open3"

module Norn
  module UI
    class SubprocessRunner
      def self.run(command, workspace_root: Norn.workspace_root)
        accumulated_stdout = ""
        accumulated_stderr = ""

        Open3.popen3(command, chdir: workspace_root) do |stdin, stdout, stderr, wait_thr|
          stdin.close

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
        Norn::Execution::Outcome.new(
          stderr: "Failed to spawn process: command not found - #{e.message}",
          exit_code: 127
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/ui/subprocess_runner_spec.rb`
Expected: PASS

- [ ] **Step 5: Require the new file in lib/norn.rb**

Modify: `lib/norn.rb` to require the subprocess runner. Add near other requires (e.g. line 23):
```ruby
require_relative "norn/ui/subprocess_runner"
```

Run entire test suite:
`bundle exec rspec`
Expected: PASS (all 240+ specs green)

- [ ] **Step 6: Commit**

```bash
git add lib/norn.rb lib/norn/ui/subprocess_runner.rb spec/norn/ui/subprocess_runner_spec.rb
git commit -m "feat(subprocess): implement Threaded SubprocessRunner with real-time yielding"
```

---

### Task 3: Build Security Command Validator Guard

**Files:**
- Create: `lib/norn/execution/command_validator.rb`
- Test: `spec/norn/execution/command_validator_spec.rb`

**Interfaces:**
- Consumes: None
- Produces: `Norn::Execution::CommandValidator` singleton class exposing:
  * `.validate!(command)` returning `nil` or raising `SecurityError`

- [ ] **Step 1: Write the failing validator specs**

Create the spec file `spec/norn/execution/command_validator_spec.rb`:
```ruby
require "spec_helper"
require_relative "../../../lib/norn/execution/command_validator"

RSpec.describe Norn::Execution::CommandValidator do
  describe ".validate!" do
    it "allows safe execution commands" do
      expect { described_class.validate!("git status") }.not_to raise_error
      expect { described_class.validate!("bundle exec rspec spec") }.not_to raise_error
      expect { described_class.validate!("echo 'hello'") }.not_to raise_error
    end

    it "blocks sudo actions to prevent privilege escalation" do
      expect {
        described_class.validate!("sudo apt-get install git")
      }.to raise_error(SecurityError, /escalation/)
    end

    it "blocks destructive rm -rf / commands" do
      expect {
        described_class.validate!("rm -rf /")
      }.to raise_error(SecurityError, /destructive/)
    end

    it "blocks destructive rm -rf * commands" do
      expect {
        described_class.validate!("rm -rf *")
      }.to raise_error(SecurityError, /destructive/)
    end

    it "blocks direct raw disk write utilities" do
      expect {
        described_class.validate!("dd if=/dev/zero of=/dev/sda")
      }.to raise_error(SecurityError, /destructive/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/execution/command_validator_spec.rb`
Expected: FAIL (cannot load such file -- command_validator)

- [ ] **Step 3: Write minimal implementation**

Create `lib/norn/execution/command_validator.rb`:
```ruby
module Norn
  module Execution
    class CommandValidator
      BLACKLIST = [
        [/\bsudo\b/i, "Prevent root privilege escalation!"],
        [/rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\//, "Prevent destructive rm -rf / commands!"],
        [/rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\*/, "Prevent destructive rm -rf * workspace wipes!"],
        [/rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\./, "Prevent destructive rm -rf . current folder wipes!"],
        [/>\s*\/dev\/(?:sda|sdb|nvme)/, "Prevent direct raw disk blocks writing!"],
        [/\bdd\b.*if=.*of=\/dev\//, "Prevent raw device block copies!"]
      ].freeze

      def self.validate!(command)
        BLACKLIST.each do |pattern, message|
          if command =~ pattern
            raise SecurityError, "Execution Blocked: #{message}"
          end
        end
        nil
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/execution/command_validator_spec.rb`
Expected: PASS

- [ ] **Step 5: Require the validator in lib/norn.rb**

Modify: `lib/norn.rb` to require the validator (e.g. line 24):
```ruby
require_relative "norn/execution/command_validator"
```

Run entire test suite:
`bundle exec rspec`
Expected: PASS (all green)

- [ ] **Step 6: Commit**

```bash
git add lib/norn.rb lib/norn/execution/command_validator.rb spec/norn/execution/command_validator_spec.rb
git commit -m "feat(subprocess): implement CommandValidator to block catastrophic commands"
```

---

### Task 4: Integrate the Subprocess Tools Plugin and `execute_command` Tool

**Files:**
- Create: `plugins/subprocess_tools/plugin.rb`
- Test: `spec/plugins/subprocess_tools/plugin_spec.rb`

**Interfaces:**
- Consumes: `Norn::UI::SubprocessRunner`, `Norn::Execution::CommandValidator`, `Norn::Execution::Outcome`
- Produces: `SubprocessToolsPlugin` registering:
  * `execute_command` tool taking: `command` [String]
  * Statically declared `dangerous: true` and mapped to capability `:sys_execute`.
  * Outputs the stdout/stderr stream directly to Norn's `@output` during interactive runs.
  * Captures security blocks to return a monadic `Failure(Norn::FailurePayload)`.

- [ ] **Step 1: Write failing plugin integration specs**

Create the spec file `spec/plugins/subprocess_tools/plugin_spec.rb`:
```ruby
require "spec_helper"
require_relative "../../../plugins/subprocess_tools/plugin"

RSpec.describe SubprocessToolsPlugin, norn_plugins: :subprocess_tools do
  let(:registry) { Norn::ToolRegistry }

  before do
    Norn::ToolRegistry.clear!
    Norn::PluginManager.trigger(:on_tool_register, Norn::ToolRegistry)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  it "registers the execute_command tool correctly" do
    tool = registry.resolve("execute_command")
    expect(tool).not_to be_nil
    expect(tool.required_capabilities).to eq([:sys_execute])
    expect(tool.dangerous?).to be(true)
  end

  it "executes a safe command and returns the text result" do
    tool = registry.resolve("execute_command")
    result = tool.call(command: "echo 'plugin execution'")
    expect(result.strip).to eq("plugin execution")
  end

  it "raises security error and triggers monad failure on blacklisted inputs" do
    tool = registry.resolve("execute_command")
    expect {
      tool.call(command: "sudo rm -rf /")
    }.to raise_error(SecurityError)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/plugins/subprocess_tools/plugin_spec.rb`
Expected: FAIL (cannot load such file -- plugin)

- [ ] **Step 3: Write minimal implementation**

Create `plugins/subprocess_tools/plugin.rb`:
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
      
      # 1. Run strict security validation checks
      Norn::Execution::CommandValidator.validate!(command)

      # 2. Extract output stream from calling mode context if available, otherwise fallback to stdout
      output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout

      # 3. Execute process with concurrent stream readers
      outcome = Norn::UI::SubprocessRunner.run(command) do |stream_type, chunk|
        if stream_type == :stderr
          # Print error streams in red / warning colors
          output_stream.print "\e[1;31m#{chunk}\e[0m"
        else
          output_stream.print chunk
        end
      end

      # Return the string representation of the outcome back to the caller
      outcome.to_s
    end

    registry.register(execute_command_tool)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/plugins/subprocess_tools/plugin_spec.rb`
Expected: PASS

- [ ] **Step 5: Run the entire test suite to guarantee 100% stability**

Run: `bundle exec rspec`
Expected: PASS (all 240+ specs green and fully passing)

- [ ] **Step 6: Commit**

```bash
git add plugins/subprocess_tools/plugin.rb spec/plugins/subprocess_tools/plugin_spec.rb
git commit -m "feat(subprocess): integrate SubprocessToolsPlugin and execute_command tool"
```
