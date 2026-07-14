# Interactive Gatekeeper Prompts and Post-Abort Fallbacks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Norn's gatekeeper prompts into beautiful, single-keystroke interactive select menus using `TTY::Prompt` and implement post-abort fallbacks (Skip, Edit parameters via LLM feedback, Abort).

**Architecture:** We isolate all interactive UI prompting and parameter refinement into a dedicated service `Norn::UI::Gatekeeper` to maintain clean separation of concerns and absolute testability. Core execution in `Norn::Mode` delegates checks to this service.

**Tech Stack:** Ruby, RSpec, `tty-prompt`, `dry-monads`

## Global Constraints
- Target ruby version: 3.x or 4.x (compatible with Gemfile)
- Strict unit testing with 100% test isolation (no real external network calls or standard stream contamination)
- Any newly introduced files must live strictly inside `lib/norn/` or `plugins/` namespaces.

---

### Task 1: Build Gatekeeper Skeleton and Capability Authorization

**Files:**
- Create: `lib/norn/ui/gatekeeper.rb`
- Test: `spec/norn/ui/gatekeeper_spec.rb`

**Interfaces:**
- Consumes: None
- Produces: `Norn::UI::Gatekeeper` service with `#authorize_capabilities(tool_name, caps, args)` returning `true` (authorized) or `false` (denied).

- [ ] **Step 1: Write the failing unit tests for capability authorization**

Create `spec/norn/ui/gatekeeper_spec.rb` with these specifications:
```ruby
require "spec_helper"
require "stringio"
require "norn/ui/gatekeeper"

RSpec.describe Norn::UI::Gatekeeper do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  subject { described_class.new(input: input, output: output) }

  describe "#authorize_capabilities" do
    it "returns true when user selects Yes" do
      # Simulate selecting Yes in tty-prompt select (usually first option/index)
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(true)
      result = subject.authorize_capabilities("file_write", [:sys_write], { path: "test.txt" })
      expect(result).to be true
      expect(output.string).to include("Security Escalation")
    end

    it "returns false when user selects No" do
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(false)
      result = subject.authorize_capabilities("file_write", [:sys_write], { path: "test.txt" })
      expect(result).to be false
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: FAIL with `LoadError: cannot load such file -- norn/ui/gatekeeper`

- [ ] **Step 3: Create the class and write minimal implementation**

Create `lib/norn/ui/gatekeeper.rb` with:
```ruby
require "tty-prompt"

module Norn
  module UI
    class Gatekeeper
      def initialize(input: $stdin, output: $stdout)
        @input = input
        @output = output
        @prompt = TTY::Prompt.new(input: input, output: output)
      end

      def authorize_capabilities(tool_name, caps, args)
        @output.puts "\n⚠️  Security Escalation: Tool '#{tool_name}' requested unauthorized capabilities: #{caps.join(', ')}"
        @output.puts "Arguments: #{args.inspect}"

        choices = {
          "🔓 Yes, authorize these capabilities" => true,
          "🚫 No, deny authorization" => false
        }
        @prompt.select("Do you want to authorize this operation?", choices)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/norn/ui/gatekeeper.rb spec/norn/ui/gatekeeper_spec.rb
git commit -m "feat: implement Gatekeeper skeleton and capability authorization"
```

---

### Task 2: Implement Gatekeeper Danger Authorization

**Files:**
- Modify: `lib/norn/ui/gatekeeper.rb`
- Test: `spec/norn/ui/gatekeeper_spec.rb`

**Interfaces:**
- Consumes: `Norn::UI::Gatekeeper` constructor
- Produces: `Gatekeeper#authorize_danger(tool, args)` returning `true` or `false`.

- [ ] **Step 1: Write the failing tests for danger authorization**

Append to `spec/norn/ui/gatekeeper_spec.rb` inside the describe block:
```ruby
  describe "#authorize_danger" do
    let(:tool) { double("Norn::Tool", name: "file_write", dangerous?: true) }

    it "renders file diff and returns true when user selects Yes" do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return("old content")
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(true)

      result = subject.authorize_danger(tool, { path: "test.txt", content: "new content" })
      expect(result).to be true
      expect(output.string).to include("Proposed changes to")
    end

    it "handles generic dangerous commands and returns false when user selects No" do
      generic_tool = double("Norn::Tool", name: "bash_exec", dangerous?: true)
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(false)

      result = subject.authorize_danger(generic_tool, { command: "rm -rf /" })
      expect(result).to be false
      expect(output.string).to include("potentially dangerous command")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: FAIL with `undefined method authorize_danger`

- [ ] **Step 3: Implement `authorize_danger` in `Gatekeeper`**

Modify `lib/norn/ui/gatekeeper.rb` by adding:
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
          "🚫 No, abort/review" => false
        }
        @prompt.select("Execute this action?", choices)
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/norn/ui/gatekeeper.rb spec/norn/ui/gatekeeper_spec.rb
git commit -m "feat: implement gatekeeper danger authorization"
```

---

### Task 3: Implement Post-Abort Fallback Menu

**Files:**
- Modify: `lib/norn/ui/gatekeeper.rb`
- Test: `spec/norn/ui/gatekeeper_spec.rb`

**Interfaces:**
- Consumes: None
- Produces: `Gatekeeper#show_fallback_menu(tool_name, args)` returning `:skip`, `:edit`, or `:abort`.

- [ ] **Step 1: Write the failing tests for fallback menu**

Append to `spec/norn/ui/gatekeeper_spec.rb`:
```ruby
  describe "#show_fallback_menu" do
    it "presents choices and returns the corresponding symbol" do
      expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(:edit)
      result = subject.show_fallback_menu("file_write", { path: "test.txt" })
      expect(result).to eq(:edit)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: FAIL with `undefined method show_fallback_menu`

- [ ] **Step 3: Implement `show_fallback_menu` in `Gatekeeper`**

Add the method to `lib/norn/ui/gatekeeper.rb`:
```ruby
      def show_fallback_menu(tool_name, args)
        choices = {
          "Skip this execution (allow agent to continue without this result)" => :skip,
          "Edit command arguments inline (freeform feedback)" => :edit,
          "Abort the active agent session completely" => :abort
        }
        @prompt.select("\nOperation Aborted. What would you like to do next?", choices)
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/norn/ui/gatekeeper.rb spec/norn/ui/gatekeeper_spec.rb
git commit -m "feat: implement show_fallback_menu"
```

---

### Task 4: Implement LLM Parameter Refinement and Symbolization Helper

**Files:**
- Modify: `lib/norn/ui/gatekeeper.rb`
- Test: `spec/norn/ui/gatekeeper_spec.rb`

**Interfaces:**
- Consumes: `Gatekeeper#refine_arguments(tool, args, user_feedback, client)`
- Produces: `Gatekeeper#refine_arguments` returning `Success(symbolized_args_hash)` or `Failure(error_string)`. Also provides the robust prompt and markdown cleanup.

- [ ] **Step 1: Write the failing tests for refinement and cleanup**

Append to `spec/norn/ui/gatekeeper_spec.rb`:
```ruby
  describe "#refine_arguments" do
    let(:tool) { double("Norn::Tool", name: "file_write", description: "Write file", parameters: { type: "object" }) }
    let(:client) { double("LLMClient") }

    it "returns success and symbolizes parsed JSON from LLM response" do
      # Mock the LLM provider response structure
      llm_response = double("LLMResponse")
      allow(llm_response).to receive(:is_a?).with(Hash).and_return(true)
      allow(llm_response).to receive(:[]).with(:content).and_return("```json\n{\"path\": \"new_path.txt\", \"content\": \"hello\"}\n```")
      
      expect(client).to receive(:call).and_return(double("DryMonadResult", failure?: false, value!: llm_response))

      result = subject.refine_arguments(tool, { path: "old.txt" }, "change path to new_path.txt and content to hello", client)
      expect(result.success?).to be true
      expect(result.value!).to eq({ path: "new_path.txt", content: "hello" })
    end

    it "returns failure when LLM response has invalid JSON" do
      llm_response = double("LLMResponse")
      allow(llm_response).to receive(:is_a?).with(Hash).and_return(false)
      allow(llm_response).to receive(:to_s).and_return("invalid non-json string")

      expect(client).to receive(:call).and_return(double("DryMonadResult", failure?: false, value!: llm_response))

      result = subject.refine_arguments(tool, { path: "old.txt" }, "make changes", client)
      expect(result.failure?).to be true
      expect(result.failure).to include("Invalid JSON returned by refiner LLM")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: FAIL with `undefined method refine_arguments`

- [ ] **Step 3: Implement `refine_arguments` and symbolization helper in `Gatekeeper`**

Add the code to `lib/norn/ui/gatekeeper.rb`:
```ruby
      require "dry/monads"
      include Dry::Monads[:result]

      def refine_arguments(tool, args, user_feedback, client)
        prompt = <<~PROMPT
          You are a precise tool parameter refiner. Your task is to update the parameters of a tool based on user feedback.

          Tool Name: #{tool.name}
          Tool Description: #{tool.description}
          Tool Schema: #{tool.parameters.to_json}

          Original Parameters: #{args.to_json}

          User Feedback: #{user_feedback}

          Analyze the user's feedback, apply requested changes to the original parameters, and ensure they conform to the tool schema.
          Output ONLY a raw, valid JSON object containing the updated parameters.
          Do NOT wrap output in markdown codeblocks. Do NOT add extra explanation or prose.
        PROMPT

        response_result = client.call([{ role: "user", content: prompt }])
        return response_result if response_result.failure?

        response = response_result.value!
        response_text = response.is_a?(Hash) ? response[:content] : response.to_s

        # Robust cleaning of markdown backticks if LLM ignores instruction
        cleaned_text = response_text.gsub(/```json|```/, "").strip

        begin
          parsed = JSON.parse(cleaned_text)
          Success(symbolize_keys(parsed))
        rescue => e
          Failure("Invalid JSON returned by refiner LLM: #{e.message}")
        end
      end

      private

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        end
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/ui/gatekeeper_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/norn/ui/gatekeeper.rb spec/norn/ui/gatekeeper_spec.rb
git commit -m "feat: implement refine_arguments in Gatekeeper"
```

---

### Task 5: Integrate UI Gatekeeper inside `Norn::Mode`

**Files:**
- Modify: `lib/norn/mode.rb`
- Test: `spec/norn/mode_gatekeeper_spec.rb`

**Interfaces:**
- Consumes: `Norn::UI::Gatekeeper` service
- Produces: Seamless recursive gatekeeping prompting, handling edits, skips, and complete aborts cleanly.

- [ ] **Step 1: Write integration specs for recursive gatekeeper behavior**

Create a new test file `spec/norn/mode_gatekeeper_spec.rb` simulating capability and danger checks, edits, and skips:
```ruby
require "spec_helper"
require "norn/mode"
require "norn/ui/gatekeeper"

# Define concrete dummy class to test abstract Mode integration
class DummyMode < Norn::Mode
  def interactive?; true; end
  def allowed_capabilities; @allowed_capabilities ||= []; end
  def instructions; "Do things"; end
  def banner_name; "Dummy Mode"; end
end

RSpec.describe "Mode Gatekeeper Integration" do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  subject { DummyMode.new(input: input, output: output) }

  before do
    # Register a dangerous tool requiring capabilities
    Norn::ToolRegistry.registered_tools.clear
    Norn::ToolRegistry.register(Norn::Tool.new(
      "write_secret", "Write a secret file", { type: "object", properties: { secret: { type: "string" } } },
      required_capabilities: [:sys_write], dangerous: true
    ) { |args| "Secret written: #{args[:secret]}" })
  end

  it "handles skip, edit loops, and success integration" do
    # Initialize our gatekeeper mock
    gatekeeper = double("Norn::UI::Gatekeeper")
    allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)

    # 1. First capability escalation check fails/unauthorized, user triggers edit
    expect(gatekeeper).to receive(:authorize_capabilities).and_return(false)
    expect(gatekeeper).to receive(:show_fallback_menu).and_return(:edit)
    expect(gatekeeper).to receive(:show_fallback_menu).never # should break into edit flow first
    
    # Simulate LLM client and feedback prompting
    client = double("LLMClient")
    allow(Norn::Container).to receive(:[]).with("llm.openai").and_return(client)
    allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("change secret to banana")
    
    # Mock LLM refinement returning updated symbolized parameters
    expect(gatekeeper).to receive(:refine_arguments).and_return(Dry::Monads::Success({ secret: "banana" }))

    # 2. Recurses! Now with updated arguments. Capability authorizes this time (allowed list modified in first run, or mock success)
    expect(gatekeeper).to receive(:authorize_capabilities).and_return(true)
    
    # 3. Danger guard is triggered. User selects Yes.
    expect(gatekeeper).to receive(:authorize_danger).and_return(true)

    result = subject.execute_tool("write_secret", { secret: "apple" })
    expect(result.success?).to be true
    expect(result.value!).to eq("Secret written: banana")
  end

  it "returns success and tells LLM when skipped by user request" do
    gatekeeper = double("Norn::UI::Gatekeeper")
    allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)

    expect(gatekeeper).to receive(:authorize_capabilities).and_return(false)
    expect(gatekeeper).to receive(:show_fallback_menu).and_return(:skip)

    result = subject.execute_tool("write_secret", { secret: "apple" })
    expect(result.success?).to be true
    expect(result.value!).to eq("Tool execution skipped by user request.")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/norn/mode_gatekeeper_spec.rb`
Expected: FAIL with capability/danger text prompt mismatch (as `lib/norn/mode.rb` still uses old raw text line reads)

- [ ] **Step 3: Modify `lib/norn/mode.rb` to route through Gatekeeper**

Update `execute_tool` inside `lib/norn/mode.rb` to:
```ruby
    # Secure gatekeeper to execute registered tools safely under capability & danger policies
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

      # 2. In-Flight Interactive Danger Guards
      if tool.dangerous?(args) && interactive?
        authorized = gatekeeper.authorize_danger(tool, args)
        if authorized
          @output.puts "🔓 Action authorized."
        else
          @output.puts "🚫 Action aborted by user."
          return handle_gatekeeper_fallback(tool, args, gatekeeper)
        end
      end

      # 3. Proceed to safe execution, passing self as context
      begin
        result_str = tool.call(args, self).to_s
        Norn::PluginManager.trigger(:after_tool_call, tool_name, args, result_str, nil)
        Success(result_str)
      rescue => e
        error_msg = e.message
        Norn::PluginManager.trigger(:after_tool_call, tool_name, args, nil, error_msg)
        Success("Error executing tool '#{tool_name}': #{error_msg}")
      end
    end

    private

    def handle_gatekeeper_fallback(tool, args, gatekeeper)
      choice = gatekeeper.show_fallback_menu(tool.name, args)
      case choice
      when :skip
        Success("Tool execution skipped by user request.")
      when :edit
        # Freeform interactive parameter editing
        loop do
          prompt_helper = TTY::Prompt.new(input: @input, output: @output)
          user_feedback = prompt_helper.ask("Describe the changes you want to make: ")
          if user_feedback.nil? || user_feedback.strip.empty?
            @output.puts "No feedback provided."
            next
          end

          provider = Norn.config.llm_provider
          client = Norn::Container["llm.#{provider}"]

          refine_result = gatekeeper.refine_arguments(tool, args, user_feedback, client)
          if refine_result.success?
            new_args = refine_result.value!
            @output.puts "🔧 Modified arguments: #{new_args.inspect}"
            # Recursively call execute_tool to validate edited parameters back through gatekeeper
            return execute_tool(tool.name, new_args)
          else
            @output.puts "❌ Error refining parameters: #{refine_result.failure}"
            sub_choices = {
              "Try describing changes again" => :try_again,
              "Go back to fallback menu" => :back_to_menu
            }
            sub_choice = prompt_helper.select("How would you like to proceed?", sub_choices)
            if sub_choice == :back_to_menu
              return handle_gatekeeper_fallback(tool, args, gatekeeper)
            end
          end
        end
      else
        Failure(Norn::FailurePayload.new(
          Norn::ToolError.new("Action aborted by user."),
          { tool: tool.name, args: args }
        ))
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/norn/mode_gatekeeper_spec.rb`
Expected: PASS

- [ ] **Step 5: Run full Spec suite to make sure nothing is broken**

Run: `bundle exec rspec`
Expected: 211+ passing specs, 0 failures!

- [ ] **Step 6: Commit**

```bash
git add lib/norn/mode.rb spec/norn/mode_gatekeeper_spec.rb
git commit -m "feat: integrate UI Gatekeeper inside Norn::Mode and execute_tool"
```
