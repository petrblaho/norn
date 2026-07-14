# Statically Dangerous Session Approvals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to approve statically dangerous tools (like `file_write` and `file_edit`) for the active session so they can bypass subsequent interactive prompts, while ensuring dynamically dangerous tools (like `git`) still prompt for dangerous subcommands. We will also clean up the Gatekeeper UI to only show the session-approval option when it's safe to do so.

**Architecture:** Implement `allow_session_danger?` on `Norn::Tool` returning `@dangerous` by default. Update `session_approved?` to respect it. Override `allow_session_danger?` in `GitTool` to return `false` to keep its safe/dangerous boundaries. Hide the session-level approval option in Gatekeeper for tools that are statically dangerous but don't yet have session approvals enabled/active.

**Tech Stack:** Ruby, RSpec

## Global Constraints

- No external API/network requests in specs.
- Run tests after each task and commit frequently.
- Follow TDD (Red-Green-Refactor) practices.

---

### Task 1: Update Norn::Tool contract and session_approved?

**Files:**
- Modify: `lib/norn/tool.rb`
- Test: `spec/norn/tool_spec.rb`

**Interfaces:**
- Consumes: None
- Produces: `Tool#allow_session_danger?`, updated `Tool#session_approved?(session, args)`

- [ ] **Step 1: Write the failing tests**
  Add tests to `spec/norn/tool_spec.rb` to assert the new behavior.
  
  ```ruby
  describe "allow_session_danger?" do
    it "defaults to true if the tool is statically dangerous" do
      dangerous_tool = Norn::Tool.new("danger", "desc", {}, dangerous: true) { "ok" }
      expect(dangerous_tool.allow_session_danger?).to be true
    end

    it "defaults to false if the tool is not statically dangerous" do
      safe_tool = Norn::Tool.new("safe", "desc", {}, dangerous: false) { "ok" }
      expect(safe_tool.allow_session_danger?).to be false
    end
  end

  describe "session_approved? with statically dangerous tool" do
    let(:dangerous_tool) { Norn::Tool.new("danger", "desc", {}, dangerous: true) { "ok" } }
    let(:session) { double("Session") }

    it "returns true if the session contains the approval and the tool allows session danger" do
      allow(session).to receive(:get).with(:session_approvals).and_return([{ tool_name: "danger" }])
      expect(dangerous_tool.session_approved?(session, {})).to be true
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/norn/tool_spec.rb`
  Expected: FAIL (missing `allow_session_danger?` method, or `session_approved?` returning false)

- [ ] **Step 3: Write minimal implementation**
  In `lib/norn/tool.rb`, add `allow_session_danger?` and update `session_approved?`:
  ```ruby
    def allow_session_danger?
      @dangerous
    end

    def session_approved?(session, args)
      return false if session.nil?
      
      approvals = session.get(:session_approvals) || []
      has_approval = approvals.any? { |app| app[:tool_name] == name }
      
      has_approval && (!dangerous?(args) || allow_session_danger?)
    end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/norn/tool_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add lib/norn/tool.rb spec/norn/tool_spec.rb
  git commit -m "feat(tool): add allow_session_danger? and update session_approved?"
  ```

---

### Task 2: Specialize GitTool allow_session_danger?

**Files:**
- Modify: `plugins/git/plugin.rb`
- Test: `spec/plugins/git/plugin_spec.rb`

**Interfaces:**
- Consumes: `Norn::Tool`
- Produces: `GitTool#allow_session_danger?` returning `false`

- [ ] **Step 1: Write the failing test**
  Add a spec to `spec/plugins/git/plugin_spec.rb`:
  ```ruby
  describe "#allow_session_danger?" do
    it "returns false so dangerous git subcommands still prompt" do
      expect(tool.allow_session_danger?).to be false
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/plugins/git/plugin_spec.rb`
  Expected: FAIL (returns `true` because it delegates to the base `@dangerous` default, which is `false` but should be explicitly `false`)

- [ ] **Step 3: Write minimal implementation**
  In `plugins/git/plugin.rb`, define `allow_session_danger?` on `GitTool` class:
  ```ruby
        def allow_session_danger?
          false
        end
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/plugins/git/plugin_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add plugins/git/plugin.rb spec/plugins/git/plugin_spec.rb
  git commit -m "feat(git): specialize GitTool#allow_session_danger? to return false"
  ```

---

### Task 3: Hide session option in Gatekeeper for statically dangerous tools unless approved

**Files:**
- Modify: `lib/norn/ui/gatekeeper.rb`
- Test: `spec/norn/ui/gatekeeper_spec.rb`

**Interfaces:**
- Consumes: `Norn::Tool#dangerous`
- Produces: Conditional `:session` option in `Gatekeeper#authorize_danger`

- [ ] **Step 1: Write the failing test**
  Modify the `spec/norn/ui/gatekeeper_spec.rb` to verify the conditional option.
  We will update the double of the `tool` and add a new test for a statically dangerous tool.
  ```ruby
  it "does NOT include the session approval option if the tool is statically dangerous" do
    tool_mock = double("Tool", name: "write_secret", dangerous: true, dangerous?: true, session_approval_label: "Approve 'write_secret' for the rest of this session")
    prompt = double("Prompt")
    allow(TTY::Prompt).to receive(:new).and_return(prompt)
    
    expect(prompt).to receive(:select).with(
      "Execute this action?",
      hash_not_including("⚡ Approve 'write_secret' for the rest of this session" => :session)
    ).and_return(true)

    result = subject.authorize_danger(tool_mock, {})
    expect(result).to be true
  end
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
  Expected: FAIL

- [ ] **Step 3: Write minimal implementation**
  In `lib/norn/ui/gatekeeper.rb`, update `authorize_danger`:
  ```ruby
        choices = {
          "🔓 Yes, proceed" => true,
          "🚫 No, abort/review" => false
        }
        
        # Only offer session-level approvals for tools that are not statically dangerous
        unless tool.respond_to?(:dangerous) && tool.dangerous
          choices["⚡ #{tool.session_approval_label(args)}"] = :session
        end
        
        @prompt.select("Execute this action?", choices)
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add lib/norn/ui/gatekeeper.rb spec/norn/ui/gatekeeper_spec.rb
  git commit -m "feat(gatekeeper): hide session option for statically dangerous tools"
  ```
