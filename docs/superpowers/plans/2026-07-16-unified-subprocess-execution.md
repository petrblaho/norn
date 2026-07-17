# Unified Subprocess Execution & Composable Hook Network Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `GitPlugin` and `RSpecPlugin` to use safe shell delegation over Norn's stateful subprocess pipeline, enabling full hook-based composability (such as dynamic command rewrites via the `rtk` plugin) and shared working directory/environment states.

**Architecture:** We securely compile structured array arguments using Ruby's `Shellwords.join`, run them through the `:before_subprocess_execute` middleware hook, and execute them on `Norn::Container["subprocess.shell"]` (if registered) with real-time stream yielding or fallback to `Open3.capture3` if unregistered.

**Tech Stack:** Ruby, RSpec, Dry-Monads, Open3, Shellwords

## Global Constraints
- **Version Compatibility:** Maintain clean compatibility with Ruby 3.x.
- **Safety Guarantee:** Use standard `Shellwords.join` to compile command arrays, ensuring absolute protection against shell injection vulnerabilities.
- **Backward Compatibility:** Maintain a fallback execution path (`Open3.capture3`) so the plugins continue to function in minimal bootstrap/test environments where `subprocess.shell` is not registered.

---

### Task 1: Refactor GitPlugin to use Safe Shell Delegation

**Files:**
- Modify: `plugins/git/plugin.rb`
- Modify: `spec/plugins/git/plugin_spec.rb`

**Interfaces:**
- Consumes: `Norn::Container["subprocess.shell"]` and `Norn::PluginManager.trigger_middleware(:before_subprocess_execute)`
- Produces: `GitPlugin` executing securely via the stateful/fallback subshell pipeline.

- [ ] **Step 1: Implement safe shell delegation in `GitPlugin`**
  Modify the `git_tool` initialization inside `plugins/git/plugin.rb` (lines 106-133) to safely join commands using `Shellwords`, trigger the `:before_subprocess_execute` hook, and run using the subshell (if available) with real-time progress yielding, otherwise falling back to `Open3.capture3`.
  
  Replace the block in `plugins/git/plugin.rb` with:
  ```ruby
    ) do |args, context|
      subcmd = args[:subcommand]
      extra_args = Array(args[:arguments]).map(&:to_s)

      if subcmd == "commit"
        payload = { subcommand: subcmd, arguments: extra_args }
        middleware_result = Norn::PluginManager.trigger_middleware(:before_git_commit, payload)
        if middleware_result.success?
          extra_args = middleware_result.value![:arguments]
        end
      end

      require "shellwords"
      cmd = ["git", subcmd] + extra_args
      command_str = Shellwords.join(cmd)

      # Trigger the before_subprocess_execute middleware hook
      payload = { command: command_str }
      before_result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
      sanitized_command = before_result.success? ? before_result.value![:command] : command_str

      begin
        root = File.expand_path(Norn.workspace_root)
        if Norn::Container.key?("subprocess.shell")
          subshell = Norn::Container["subprocess.shell"]
          output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout
          
          outcome = subshell.execute(sanitized_command) do |stream_type, chunk|
            Norn::PluginManager.trigger(:on_subprocess_output, {
              stream: stream_type,
              chunk: chunk
            })

            if stream_type == :stderr
              output_stream.print "\e[1;31m#{chunk}\e[0m"
            else
              output_stream.print chunk
            end
          end
          
          if outcome.success?
            outcome.stdout.empty? ? "Command executed successfully (no output)." : outcome.stdout
          else
            "Error executing git #{subcmd}:\n#{outcome.stderr}\n#{outcome.stdout}"
          end
        else
          stdout, stderr, status = Open3.capture3(sanitized_command, chdir: root)

          if status.success?
            stdout.empty? ? "Command executed successfully (no output)." : stdout
          else
            "Error executing git #{subcmd}: #{stderr}\n#{stdout}"
          end
        end
      rescue => e
        "Failed to run git command: #{e.message}"
      end
    end
  ```

- [ ] **Step 2: Update existing GitPlugin specs**
  Since `GitPlugin` now passes a single `Shellwords`-escaped string to `Open3.capture3` instead of an array, update the test mocks inside `spec/plugins/git/plugin_spec.rb` to expect a string.
  
  In `spec/plugins/git/plugin_spec.rb` around line 115, change:
  ```ruby
  expect(Open3).to receive(:capture3).with("git", "status", "-s", chdir: anything).and_return(...)
  ```
  to:
  ```ruby
  expect(Open3).to receive(:capture3).with("git status -s", chdir: anything).and_return(...)
  ```
  
  Around line 124, change:
  ```ruby
  expect(Open3).to receive(:capture3).with("git", "checkout", "non-existent", chdir: anything).and_return(...)
  ```
  to:
  ```ruby
  expect(Open3).to receive(:capture3).with("git checkout non-existent", chdir: anything).and_return(...)
  ```

- [ ] **Step 3: Add new unit and integration tests for Git hook interception and subshell execution**
  Add a new context block inside `spec/plugins/git/plugin_spec.rb` before the final `end` to verify hook execution and stateful subshell routing:
  ```ruby
    context "when running through unified execution" do
      let(:git_tool) { registry.resolve("git") }

      it "triggers the :before_subprocess_execute middleware hook" do
        hook_triggered = false
        Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
          hook_triggered = true
          payload
        end

        allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
        git_tool.call(subcommand: "status")
        expect(hook_triggered).to be true
      end

      it "executes rewritten command returned by hook" do
        Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
          Dry::Monads::Success(payload.merge(command: "git diff"))
        end

        expect(Open3).to receive(:capture3).with("git diff", chdir: anything).and_return(["diff output", "", double(success?: true)])
        res = git_tool.call(subcommand: "status")
        expect(res).to eq("diff output")
      end

      it "uses Norn::Container['subprocess.shell'] when registered" do
        subshell = double("Subshell")
        expect(subshell).to receive(:execute).with("git status").and_return(
          Norn::Execution::Outcome.new(stdout: "status output", stderr: "", exit_code: 0)
        )
        allow(Norn::Container).to receive(:key?).with("subprocess.shell").and_return(true)
        allow(Norn::Container).to receive(:[]).with("subprocess.shell").and_return(subshell)

        res = git_tool.call(subcommand: "status")
        expect(res).to eq("status output")
      end
    end
  ```

- [ ] **Step 4: Run the Git tests and verify they pass**
  Run: `bundle exec rspec spec/plugins/git/plugin_spec.rb`
  Expected: PASS with 0 failures

- [ ] **Step 5: Commit changes**
  ```bash
  git add plugins/git/plugin.rb spec/plugins/git/plugin_spec.rb
  git commit -m "feat(git): refactor GitPlugin to use unified Safe Shell Delegation and trigger execution hooks"
  ```

---

### Task 2: Refactor RSpecPlugin to use Safe Shell Delegation

**Files:**
- Modify: `plugins/rspec/plugin.rb`
- Modify: `spec/plugins/rspec/plugin_spec.rb`

**Interfaces:**
- Consumes: `Norn::Container["subprocess.shell"]` and `Norn::PluginManager.trigger_middleware(:before_subprocess_execute)`
- Produces: `RSpecPlugin` executing securely via the stateful/fallback subshell pipeline.

- [ ] **Step 1: Implement safe shell delegation in `RSpecPlugin`**
  Modify the `rspec_tool` initialization inside `plugins/rspec/plugin.rb` to safely join commands using `Shellwords`, trigger the `:before_subprocess_execute` hook, and run using the subshell (if available) with real-time progress yielding, otherwise falling back to `Open3.capture3`.
  
  Replace the block in `plugins/rspec/plugin.rb` with:
  ```ruby
    ) do |args, context|
      root = File.expand_path(Norn.workspace_root)
      gemfile_path = File.join(root, "Gemfile")

      cmd = []
      if File.exist?(gemfile_path)
        cmd += ["bundle", "exec"]
      end
      cmd << "rspec"

      if args[:path]
        path_arg = args[:path].to_s
        if args[:line_number]
          path_arg += ":#{args[:line_number]}"
        end
        cmd << path_arg
      end

      if args[:arguments]
        cmd += Array(args[:arguments]).map(&:to_s)
      end

      require "shellwords"
      command_str = Shellwords.join(cmd)

      # Trigger the before_subprocess_execute middleware hook
      payload = { command: command_str }
      before_result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
      sanitized_command = before_result.success? ? before_result.value![:command] : command_str

      begin
        if Norn::Container.key?("subprocess.shell")
          subshell = Norn::Container["subprocess.shell"]
          output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout
          
          outcome = subshell.execute(sanitized_command) do |stream_type, chunk|
            Norn::PluginManager.trigger(:on_subprocess_output, {
              stream: stream_type,
              chunk: chunk
            })

            if stream_type == :stderr
              output_stream.print "\e[1;31m#{chunk}\e[0m"
            else
              output_stream.print chunk
            end
          end
          
          if outcome.success?
            outcome.stdout.empty? ? "Tests passed successfully (no output)." : outcome.stdout
          else
            "RSpec execution failed:\n#{outcome.stderr}\n#{outcome.stdout}"
          end
        else
          stdout, stderr, status = Open3.capture3(sanitized_command, chdir: root)

          if status.success?
            stdout.empty? ? "Tests passed successfully (no output)." : stdout
          else
            "RSpec execution failed:\n#{stderr}\n#{stdout}"
          end
        end
      rescue => e
        "Failed to run RSpec command: #{e.message}"
      end
    end
  ```

- [ ] **Step 2: Update existing RSpecPlugin specs**
  Since `RSpecPlugin` now passes a single `Shellwords`-escaped string to `Open3.capture3` instead of separate arguments, update the test mocks inside `spec/plugins/rspec/plugin_spec.rb` to expect a string.
  
  In `spec/plugins/rspec/plugin_spec.rb`:
  * Around line 63, change `.with("bundle", "exec", "rspec", chdir: anything)` to `.with("bundle exec rspec", chdir: anything)`
  * Around line 85, change `.with("rspec", chdir: anything)` to `.with("rspec", chdir: anything)`
  * Around line 107, change `.with("rspec", "spec/my_spec.rb:42", chdir: anything)` to `.with("rspec spec/my_spec.rb:42", chdir: anything)`
  * Around line 129, change `.with("rspec", "spec/my_spec.rb", "--format", "documentation", chdir: anything)` to `.with("rspec spec/my_spec.rb --format documentation", chdir: anything)`
  * Around line 151, change `.with("rspec", chdir: anything)` to `.with("rspec", chdir: anything)`

- [ ] **Step 3: Add new unit and integration tests for RSpec hook interception and subshell execution**
  Add a new context block inside `spec/plugins/rspec/plugin_spec.rb` before the final `end` to verify hook execution and stateful subshell routing:
  ```ruby
    context "when running through unified execution" do
      let(:rspec_tool) { registry.resolve("rspec") }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
          if path.end_with?("Gemfile")
            false
          else
            original_method.call(path)
          end
        end
      end

      it "triggers the :before_subprocess_execute middleware hook" do
        hook_triggered = false
        Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
          hook_triggered = true
          payload
        end

        allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
        rspec_tool.call({})
        expect(hook_triggered).to be true
      end

      it "executes rewritten command returned by hook" do
        Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
          Dry::Monads::Success(payload.merge(command: "rspec spec/other_spec.rb"))
        end

        expect(Open3).to receive(:capture3).with("rspec spec/other_spec.rb", chdir: anything).and_return(["rspec output", "", double(success?: true)])
        res = rspec_tool.call({})
        expect(res).to eq("rspec output")
      end

      it "uses Norn::Container['subprocess.shell'] when registered" do
        subshell = double("Subshell")
        expect(subshell).to receive(:execute).with("rspec").and_return(
          Norn::Execution::Outcome.new(stdout: "rspec output", stderr: "", exit_code: 0)
        )
        allow(Norn::Container).to receive(:key?).with("subprocess.shell").and_return(true)
        allow(Norn::Container).to receive(:[]).with("subprocess.shell").and_return(subshell)

        res = rspec_tool.call({})
        expect(res).to eq("rspec output")
      end
    end
  ```

- [ ] **Step 4: Run the RSpec plugin tests and verify they pass**
  Run: `bundle exec rspec spec/plugins/rspec/plugin_spec.rb`
  Expected: PASS with 0 failures

- [ ] **Step 5: Commit changes**
  ```bash
  git add plugins/rspec/plugin.rb spec/plugins/rspec/plugin_spec.rb
  git commit -m "feat(rspec): refactor RSpecPlugin to use unified Safe Shell Delegation and trigger execution hooks"
  ```

---

### Task 3: Full System Test and Integration Verification

**Files:**
- Test: All tests in the workspace (`spec/`)

**Interfaces:**
- Consumes: Fully integrated Norn system.
- Produces: 100% verified composability where RSpec and Git are fully testable, safe, and interact with the RTK rewrite plugin seamlessly.

- [ ] **Step 1: Execute all specs in the repository**
  Run: `bundle exec rspec`
  Expected: PASS with all 281+ specs green!

- [ ] **Step 2: Commit any final minor formatting/cleanup**
  ```bash
  git commit -a -m "test(integration): verify full unified subprocess integration across codebase"
  ```
