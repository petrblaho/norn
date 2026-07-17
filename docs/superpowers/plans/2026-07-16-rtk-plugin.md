# RTK Rewrite Pluggable Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a schema-validated, boot-time-detected RTK rewrite plugin for Norn that intercepts subprocess command execution and rewrites commands via `rtk rewrite`.

**Architecture:** Add schema settings to `Norn::Config`, implement `RtkPlugin < Norn::Plugin` with `respond_to?` overriding for zero-overhead dynamic hook exclusion when the binary is missing, and execute rewriting via safe subshell delegation to `rtk`.

**Tech Stack:** Ruby, Dry::Configurable, Dry::Schema, Open3, RSpec.

## Global Constraints

- **Single Source of Truth:** All command rewrite rules are managed by `rtk rewrite`.
- **Dynamic Hook Exclusion:** Plugin must not respond to `:before_subprocess_execute` if `rtk` is missing or disabled at boot-time.
- **Boot-time detection:** Look up path presence at boot, not dynamically during every tool run.

---

### Task 1: Core Configuration & Validation

**Files:**
- Modify: `lib/norn/config.rb:18-23`
- Modify: `lib/norn/config_loader.rb:14-18`
- Test: `spec/norn/config_loader_spec.rb`

**Interfaces:**
- Produces: `Norn.config.rtk_enabled`, `Norn.config.rtk_warn_if_missing`, `Norn.config.rtk_path`

- [ ] **Step 1: Edit `lib/norn/config.rb` to add settings**

Add the settings under `Norn::Config` class:
```ruby
setting :rtk_enabled, default: true
setting :rtk_warn_if_missing, default: true
setting :rtk_path, default: nil
```

- [ ] **Step 2: Edit `lib/norn/config_loader.rb` to register schema validations**

Add validation rules to the `Schema` definition:
```ruby
optional(:rtk_enabled).maybe(:bool)
optional(:rtk_warn_if_missing).maybe(:bool)
optional(:rtk_path).maybe(:string)
```

- [ ] **Step 3: Add unit tests to `spec/norn/config_loader_spec.rb`**

Add tests inside `spec/norn/config_loader_spec.rb` to verify these configurations load defaults and validate correctly:
```ruby
  describe "RTK plugin configuration" do
    before do
      @orig_enabled = Norn.config.rtk_enabled
      @orig_warn = Norn.config.rtk_warn_if_missing
      @orig_path = Norn.config.rtk_path
    end

    after do
      Norn::Config.config.update(
        rtk_enabled: @orig_enabled,
        rtk_warn_if_missing: @orig_warn,
        rtk_path: @orig_path
      )
    end

    it "loads default values for RTK settings" do
      described_class.load
      expect(Norn.config.rtk_enabled).to be true
      expect(Norn.config.rtk_warn_if_missing).to be true
      expect(Norn.config.rtk_path).to be_nil
    end

    it "allows overriding and validates boolean parameters" do
      local_path = File.join(Dir.pwd, ".norn.yml")
      allow(File).to receive(:exist?).with(local_path).and_return(true)
      allow(YAML).to receive(:load_file).with(local_path).and_return({
        rtk_enabled: false,
        rtk_warn_if_missing: false,
        rtk_path: "/usr/local/bin/rtk"
      })

      described_class.load
      expect(Norn.config.rtk_enabled).to be false
      expect(Norn.config.rtk_warn_if_missing).to be false
      expect(Norn.config.rtk_path).to eq("/usr/local/bin/rtk")
    end
  end
```

- [ ] **Step 4: Run tests to verify config loader correctness**

Run: `bundle exec rspec spec/norn/config_loader_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/norn/config.rb lib/norn/config_loader.rb spec/norn/config_loader_spec.rb
git commit -m "feat(config): add validated configurations for pluggable rtk plugin"
```

---

### Task 2: Implement RTK Pluggable Plugin

**Files:**
- Create: `plugins/rtk/plugin.rb`

**Interfaces:**
- Consumes: `Norn.config.rtk_enabled`, `Norn.config.rtk_warn_if_missing`, `Norn.config.rtk_path`
- Produces: `RtkPlugin < Norn::Plugin` implementing `before_subprocess_execute` and dynamic hook registration/exclusion via `respond_to?`.

- [ ] **Step 1: Scaffold `plugins/rtk/plugin.rb`**

Create `plugins/rtk/` directory and populate `plugins/rtk/plugin.rb` with complete implementation:
```ruby
require "open3"

module Norn
  module Plugins
    module Rtk
      class RtkPlugin < Norn::Plugin
        def self.plugin_name
          "rtk"
        end

        def initialize
          @rtk_available = check_rtk_available
          if !@rtk_available && Norn.config.rtk_enabled && Norn.config.rtk_warn_if_missing
            warn "[rtk] rtk binary not found in PATH — plugin disabled"
          end
        end

        def respond_to_missing?(method, include_private = false)
          if method.to_sym == :before_subprocess_execute
            @rtk_available && Norn.config.rtk_enabled
          else
            super
          end
        end

        def respond_to?(method, include_private = false)
          if method.to_sym == :before_subprocess_execute
            !!(@rtk_available && Norn.config.rtk_enabled)
          else
            super
          end
        end

        def before_subprocess_execute(payload)
          return payload unless @rtk_available && Norn.config.rtk_enabled

          command = payload[:command]
          return payload if command.nil? || command.to_s.strip.empty?

          rtk_bin = Norn.config.rtk_path || "rtk"

          begin
            stdout, stderr, status = Open3.capture3(rtk_bin, "rewrite", command.to_s)
            if status.success?
              rewritten = stdout.strip
              if !rewritten.empty? && rewritten != command
                payload = payload.merge(command: rewritten)
              end
            end
          rescue => e
            # Pass through unchanged
          end

          payload
        end

        private

        def check_rtk_available
          custom_path = Norn.config.rtk_path
          if custom_path
            return File.file?(custom_path) && File.executable?(custom_path)
          end

          exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
          ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |path|
            exts.each do |ext|
              exe = File.join(path, "rtk#{ext}")
              return true if File.file?(exe) && File.executable?(exe)
            end
          end
          false
        end
      end
    end
  end
end
```

- [ ] **Step 2: Commit initial code**

```bash
git add plugins/rtk/plugin.rb
git commit -m "feat(rtk): implement pluggable RTK rewrite plugin with dynamic hook exclusion"
```

---

### Task 3: Complete RTK Plugin Test Suite

**Files:**
- Create: `spec/plugins/rtk/plugin_spec.rb`

**Interfaces:**
- Consumes: `RtkPlugin`

- [ ] **Step 1: Write comprehensive test specs**

Create `spec/plugins/rtk/plugin_spec.rb` with specs covering dependency lookup, warning behaviors, hook exclusions, and command rewrites:
```ruby
require "spec_helper"
require_relative "../../../plugins/rtk/plugin"

RSpec.describe Norn::Plugins::Rtk::RtkPlugin do
  let(:plugin) { described_class.new }

  before do
    @orig_enabled = Norn.config.rtk_enabled
    @orig_warn = Norn.config.rtk_warn_if_missing
    @orig_path = Norn.config.rtk_path
  end

  after do
    Norn::Config.config.update(
      rtk_enabled: @orig_enabled,
      rtk_warn_if_missing: @orig_warn,
      rtk_path: @orig_path
    )
  end

  describe "Plugin initialization and binary detection" do
    context "when rtk is present" do
      before do
        allow_any_instance_of(described_class).to receive(:check_rtk_available).and_return(true)
      end

      it "does not emit warning and responds to execute hook" do
        expect(described_class).not_to receive(:warn)
        p = described_class.new
        expect(p.respond_to?(:before_subprocess_execute)).to be true
      end
    end

    context "when rtk is missing" do
      before do
        allow_any_instance_of(described_class).to receive(:check_rtk_available).and_return(false)
      end

      it "emits a warning and disables hook response if warn_if_missing is true" do
        Norn::Config.config.update(rtk_enabled: true, rtk_warn_if_missing: true)
        expect_any_instance_of(described_class).to receive(:warn).with(/rtk binary not found/)
        p = described_class.new
        expect(p.respond_to?(:before_subprocess_execute)).to be false
      end

      it "does not emit a warning but disables hook response if warn_if_missing is false" do
        Norn::Config.config.update(rtk_enabled: true, rtk_warn_if_missing: false)
        expect_any_instance_of(described_class).not_to receive(:warn)
        p = described_class.new
        expect(p.respond_to?(:before_subprocess_execute)).to be false
      end
    end
  end

  describe "#before_subprocess_execute" do
    let(:payload) { { command: "git status" } }

    before do
      allow_any_instance_of(described_class).to receive(:check_rtk_available).and_return(true)
    end

    context "when rtk successfully rewrites a command" do
      it "returns payload with rewritten command" do
        expect(Open3).to receive(:capture3)
          .with("rtk", "rewrite", "git status")
          .and_return(["rtk git status", "", double(success?: true)])

        result = plugin.before_subprocess_execute(payload)
        expect(result[:command]).to eq("rtk git status")
      end
    end

    context "when rtk output is the same as input" do
      it "returns the original untouched payload" do
        expect(Open3).to receive(:capture3)
          .with("rtk", "rewrite", "git status")
          .and_return(["git status", "", double(success?: true)])

        result = plugin.before_subprocess_execute(payload)
        expect(result[:command]).to eq("git status")
      end
    end

    context "when rtk command execution fails" do
      it "gracefully returns the original payload" do
        expect(Open3).to receive(:capture3)
          .with("rtk", "rewrite", "git status")
          .and_raise(RuntimeError.new("Binary crashed"))

        result = plugin.before_subprocess_execute(payload)
        expect(result[:command]).to eq("git status")
      end
    end
  end
end
```

- [ ] **Step 2: Run RSpec to verify the tests pass**

Run: `bundle exec rspec spec/plugins/rtk/plugin_spec.rb`
Expected: PASS

- [ ] **Step 3: Run the full test suite to guarantee no regressions**

Run: `bundle exec rspec`
Expected: PASS

- [ ] **Step 4: Commit tests**

```bash
git add spec/plugins/rtk/plugin_spec.rb
git commit -m "test(rtk): add comprehensive unit and integration specs for RTK plugin"
```
