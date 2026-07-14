# Session-Level Command Approvals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement safe, in-memory, session-level command approvals to eliminate interactive prompt fatigue for safe subcommands (such as `git status` or `git diff`) while ensuring dangerous commands (such as `git push`, `git commit`, `rm -rf`) statically bypass approvals and always prompt the user.

**Architecture:** Encapsulate safety and pattern matching contracts directly inside `Norn::Tool` (and `GitTool` specialization) rather than hardcoding tool specifics in `Norn::Mode` or `Norn::UI::Gatekeeper`. Core orchestrators consult the active tool to check if a call is session-approved, maintaining strict separation of concerns.

**Tech Stack:** Ruby, RSpec, Dry-Monads, TTY-Prompt, Shellwords

## Global Constraints

- Never hardcode tool names (like "git") inside `Norn::Mode` or `Norn::UI::Gatekeeper`.
- Ensure all automated specs run in under 2 seconds and do not make external API/network requests.
- All command lines parsed via `Shellwords` to safely handle parameters.
- Always symbolize keys on arguments for consistent retrieval.

---

### Task 1: Initialize Session Approvals inside Norn::Session

**Files:**
- Modify: `plugins/session/session.rb:78-90`
- Test: `spec/plugins/session/session_spec.rb`

**Interfaces:**
- Consumes: None
- Produces: Session store with `:session_approvals` initialized to an empty array.

- [ ] **Step 1: Write the failing test**
  Add a spec inside `spec/plugins/session/session_spec.rb` to verify `:session_approvals` exists and is initialized as an empty array:
  ```ruby
  it "initializes session_approvals to an empty array" do
    expect(session.get(:session_approvals)).to eq([])
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/plugins/session/session_spec.rb`
  Expected: FAIL (returns nil instead of `[]`)

- [ ] **Step 3: Write minimal implementation**
  In `plugins/session/session.rb` update `clear!`:
  ```ruby
    def clear!
      @lock.synchronize do
        @store = {
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          provider_usage: {},
          tool_calls: [],
          history: [],
          metadata: {},
          session_approvals: []
        }
      end
    end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/plugins/session/session_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add plugins/session/session.rb spec/plugins/session/session_spec.rb
  git commit -m "feat(session): initialize session_approvals key"
  ```

---

### Task 2: Implement Tool Session Approval Contract on Norn::Tool

**Files:**
- Modify: `lib/norn/tool.rb`
- Test: `spec/norn/tool_spec.rb`

**Interfaces:**
- Consumes: `Norn::Session`
- Produces: `Tool#session_approval_label(args)`, `Tool#session_approval_pattern(args)`, `Tool#session_approved?(session, args)`

- [ ] **Step 1: Write the failing test**
  Add a spec inside `spec/norn/tool_spec.rb` to assert standard contract behaviors:
  ```ruby
  describe "Session Approval Contract" do
    let(:tool) { Norn::Tool.new("dummy", "A dummy tool", {}) { "ok" } }
    let(:session) { double("Session") }

    it "provides a default session approval label" do
      expect(tool.session_approval_label({})).to eq("Approve 'dummy' for the rest of this session")
    end

    it "provides a default session approval pattern" do
      expect(tool.session_approval_pattern({})).to eq({ tool_name: "dummy" })
    end

    it "returns false for session_approved? if session is nil" do
      expect(tool.session_approved?(nil, {})).to be false
    end

    it "returns true if the session contains the approval and tool is not dangerous" do
      allow(session).to receive(:get).with(:session_approvals).and_return([{ tool_name: "dummy" }])
      expect(tool.session_approved?(session, {})).to be true
    end

    it "returns false if the tool is dangerous even if the session contains the approval" do
      allow(session).to receive(:get).with(:session_approvals).and_return([{ tool_name: "dummy" }])
      allow(tool).to receive(:dangerous?).and_return(true)
      expect(tool.session_approved?(session, {})).to be false
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/norn/tool_spec.rb`
  Expected: FAIL with `undefined method 'session_approved?'`

- [ ] **Step 3: Write minimal implementation**
  Add these methods to `Norn::Tool` in `lib/norn/tool.rb`:
  ```ruby
    def session_approval_label(args = {})
      "Approve '#{name}' for the rest of this session"
    end

    def session_approval_pattern(args = {})
      { tool_name: name }
    end

    def session_approved?(session, args)
      return false if session.nil?
      
      approvals = session.get(:session_approvals) || []
      has_approval = approvals.any? { |app| app[:tool_name] == name }
      
      has_approval && !dangerous?(args)
    end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/norn/tool_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add lib/norn/tool.rb spec/norn/tool_spec.rb
  git commit -m "feat(tool): implement default session approval contract methods"
  ```

---

### Task 3: Specialize GitTool and Implement Custom Label

**Files:**
- Modify: `plugins/git/plugin.rb:5-42`
- Test: `spec/plugins/git/plugin_spec.rb`

**Interfaces:**
- Consumes: `Norn::Tool`
- Produces: `GitTool#session_approval_label(args)` returning subcommand-friendly text.

- [ ] **Step 1: Write the failing test**
  Add a spec inside `spec/plugins/git/plugin_spec.rb` to assert custom git label:
  ```ruby
  it "returns git subcommand session approval label" do
    expect(tool.session_approval_label({})).to eq("Approve 'git <subcommand>' for the rest of this session")
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/plugins/git/plugin_spec.rb`
  Expected: FAIL (returns standard dummy label `"Approve 'git' for..."`)

- [ ] **Step 3: Write minimal implementation**
  In `plugins/git/plugin.rb`, override the label method in `GitTool`:
  ```ruby
        def session_approval_label(args = {})
          "Approve 'git <subcommand>' for the rest of this session"
        end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/plugins/git/plugin_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add plugins/git/plugin.rb spec/plugins/git/plugin_spec.rb
  git commit -m "feat(git): specialize session_approval_label for GitTool"
  ```

---

### Task 4: Integrate Session Approval Option into Gatekeeper Prompt Menu

**Files:**
- Modify: `lib/norn/ui/gatekeeper.rb:26-62`
- Test: `spec/norn/ui/gatekeeper_spec.rb`

**Interfaces:**
- Consumes: `Norn::Tool`
- Produces: `Gatekeeper#authorize_danger(tool, args)` returning `:session` when selected.

- [ ] **Step 1: Write the failing test**
  Add a spec inside `spec/norn/ui/gatekeeper_spec.rb` to verify the menu receives the session option:
  ```ruby
  it "includes the tool-defined session approval option in choices" do
    tool = double("Tool", name: "write_secret", session_approval_label: "Approve 'write_secret' for the rest of this session")
    prompt = double("Prompt")
    allow(TTY::Prompt).to receive(:new).and_return(prompt)
    
    expect(prompt).to receive(:select).with(
      "Execute this action?",
      hash_including("⚡ Approve 'write_secret' for the rest of this session" => :session)
    ).and_return(:session)

    result = subject.authorize_danger(tool, {})
    expect(result).to eq(:session)
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
  Expected: FAIL

- [ ] **Step 3: Write minimal implementation**
  In `lib/norn/ui/gatekeeper.rb`, modify `authorize_danger`:
  ```ruby
      def authorize_danger(tool, args)
        tool_name = tool.name
        
        if ["file_write", "file_edit"].include?(tool_name)
          # Interactive File Diff Previewer
          begin
            root = File.expand_path(Norn.workspace_root)
            abs_path = File.expand_path(args[:path].to_s, root)
            unless abs_path == root || abs_path.start_with?(root + File::SEPARATOR)
              raise SecurityError, "Path traversal attempt detected"
            end

            old_content = File.exist?(abs_path) ? File.read(abs_path) : ""
            new_content = if tool_name == "file_write"
                            args[:content].to_s
                          else
                            old_content.sub(args[:old_string].to_s, args[:new_string].to_s)
                          end

            @output.puts "\n📝 Proposed changes to \e[1;32m#{args[:path]}\e[0m:"
            @output.puts Norn::DiffHelper.color_diff(old_content, new_content)
          rescue => e
            @output.puts "Diff Generation Error: #{e.message}"
            return false
          end
        else
          # Generic Danger Warning
          @output.puts "\n⚠️  Warning: Norn wants to execute a potentially dangerous command: '#{tool_name}'"
          @output.puts "Arguments: #{args.inspect}"
        end

        choices = {
          "🔓 Yes, proceed" => true,
          "🚫 No, abort/review" => false,
          "⚡ #{tool.session_approval_label(args)}" => :session
        }
        @prompt.select("Execute this action?", choices)
      end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add lib/norn/ui/gatekeeper.rb spec/norn/ui/gatekeeper_spec.rb
  git commit -m "feat(gatekeeper): expose session approval choice in danger prompts"
  ```

---

### Task 5: Orchestrate Session Approvals in Norn::Mode

**Files:**
- Modify: `lib/norn/mode.rb:158-180`
- Create: `spec/norn/session_approvals_spec.rb`

**Interfaces:**
- Consumes: `Norn::Session`, `Norn::Tool`, `Norn::UI::Gatekeeper`
- Produces: Pre-flight auto-approval logic and session approval recording.

- [ ] **Step 1: Write the failing spec in `spec/norn/session_approvals_spec.rb`**
  ```ruby
  require "spec_helper"
  require "norn/mode"

  class SessionApprovalsMode < Norn::Mode
    def interactive?; true; end
    def allowed_capabilities; @allowed_capabilities ||= [:sys_execute]; end
    def instructions; "Do things"; end
    def banner_name; "Session Approvals Mode"; end
  end

  RSpec.describe "Session Approvals Integration" do
    let(:input) { StringIO.new }
    let(:output) { StringIO.new }
    let(:session) { Norn::Session.new }
    subject { SessionApprovalsMode.new(input: input, output: output) }

    before do
      allow(Norn).to receive(:[]).with("session").and_return(session)
      Norn::ToolRegistry.registered_tools.clear
      
      # Register a mock git tool
      Norn::ToolRegistry.register(
        Norn::Plugins::Git::GitTool.new("git", "Git", {}, required_capabilities: [:sys_execute]) { |args| "git executed" }
      )
    end

    it "bypasses prompts and executes if the session contains approval and command is safe" do
      session.append(:session_approvals, { tool_name: "git" })
      
      result = subject.execute_tool("git", { subcommand: "status" })
      
      expect(result.success?).to be true
      expect(result.value!).to eq("git executed")
      expect(output.string).to include("⚡ Session approved: git")
    end

    it "forces a prompt if the session has approval but command is dangerous" do
      session.append(:session_approvals, { tool_name: "git" })
      
      gatekeeper = double("Gatekeeper")
      allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)
      
      # It should NOT auto-approve because "push" is dangerous, so it should call gatekeeper
      expect(gatekeeper).to receive(:authorize_danger).and_return(true)
      
      result = subject.execute_tool("git", { subcommand: "push" })
      expect(result.success?).to be true
    end

    it "adds approval to the session if the user selects the session option" do
      gatekeeper = double("Gatekeeper")
      allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)
      
      # Simulate user selecting the :session option from the prompt
      expect(gatekeeper).to receive(:authorize_danger).and_return(:session)
      
      expect(session.get(:session_approvals)).to be_empty
      
      result = subject.execute_tool("git", { subcommand: "status" })
      expect(result.success?).to be true
      
      # Verify approval was added to session
      expect(session.get(:session_approvals)).to contain_exactly({ tool_name: "git" })
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/norn/session_approvals_spec.rb`
  Expected: FAIL

- [ ] **Step 3: Write minimal implementation**
  In `lib/norn/mode.rb`, update `execute_tool`:
  ```ruby
    def execute_tool(tool_name, args)
      # Ensure arguments are fully symbolized for consistent key access throughout the gatekeeper and diff engine
      args = symbolize_keys(args)

      tool = Norn::ToolRegistry.resolve(tool_name)
      if tool.nil?
        return Success("Error: Tool '#{tool_name}' not found in registry.")
      end

      # Load our newly encapsulated UI Gatekeeper service
      require "norn/ui/gatekeeper"
      gatekeeper = Norn::UI::Gatekeeper.new(input: @input, output: @output)

      # 1. Capability Authorization Check
      required_caps = tool.capabilities_for(args)
      missing_caps = required_caps - allowed_capabilities

      unless missing_caps.empty?
        # Handle capability escalation
        if interactive?
          authorized = gatekeeper.authorize_capabilities(tool_name, missing_caps, args)
          if authorized
            @output.puts "🔓 Operation authorized by user."
            allowed_capabilities.concat(missing_caps)
          else
            @output.puts "🚫 Operation blocked by user."
            return handle_gatekeeper_fallback(tool, args, gatekeeper)
          end
        else
          # Non-interactive block-by-default on capability violations
          @output.puts "\n❌ Security Block: Tool '#{tool_name}' requires #{missing_caps.join(', ')} which is unauthorized in non-interactive mode."
          return Failure(Norn::FailurePayload.new(
            Norn::ToolError.new("Security violation: Unauthorized capabilities requested in non-interactive mode: #{missing_caps.join(', ')}."),
            { tool: tool_name, missing_capabilities: missing_caps, mode: self.class.name }
          ))
        end
      end

      # Pre-flight Session Approval Evaluation
      session = nil
      begin
        session = Norn["session"]
      rescue => e
        # Ignore container errors if session not registered
      end

      if session && tool.session_approved?(session, args)
        @output.puts "⚡ Session approved: #{tool.name} #{args.inspect}"
        return proceed_to_execution(tool, args)
      end

      # 2. In-Flight Interactive Danger Guards
      if tool.dangerous?(args) && interactive?
        authorized = gatekeeper.authorize_danger(tool, args)
        if authorized == :session
          @output.puts "🔓 Action authorized."
          if session
            session.append(:session_approvals, tool.session_approval_pattern(args))
          end
        elsif authorized
          @output.puts "🔓 Action authorized."
        else
          @output.puts "🚫 Action aborted by user."
          return handle_gatekeeper_fallback(tool, args, gatekeeper)
        end
      end

      # 3. Proceed to safe execution
      proceed_to_execution(tool, args)
    end

    private

    def proceed_to_execution(tool, args)
      begin
        result_str = tool.call(args, self).to_s
        Norn::PluginManager.trigger(:after_tool_call, tool.name, args, result_str, nil)
        Success(result_str)
      rescue => e
        error_msg = e.message
        Norn::PluginManager.trigger(:after_tool_call, tool.name, args, nil, error_msg)
        Success("Error executing tool '#{tool.name}': #{error_msg}")
      end
    end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/norn/session_approvals_spec.rb`
  Expected: PASS

- [ ] **Step 5: Run all test files to ensure absolutely no regressions**
  Run: `bundle exec rspec`
  Expected: ALL 219+ specs PASS

- [ ] **Step 6: Commit**
  ```bash
  git add lib/norn/mode.rb spec/norn/session_approvals_spec.rb
  git commit -m "feat(mode): orchestrate session approvals pre-flight and caching"
  ```
