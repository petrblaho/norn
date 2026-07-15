# Gemify Norn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package Norn as a gem (gemify) so it can be installed locally or run seamlessly from another Ruby project (like `compliance-backend`), solving dependency load errors.

**Architecture:** Create a `norn.gemspec` declaring all dependencies, modify the Gemfile to load from the gemspec, and update `bin/norn` to gracefully set up the environment depending on how and where it is executed.

**Tech Stack:** Ruby, RubyGems, Bundler

## Global Constraints

- Must retain full compatibility with existing plugins and test suites.
- Must support installation via `gem install` as well as referencing via `:path` in another project's Gemfile.
- No hard dependencies on Bundler when running as an installed gem, but fully compatible with `bundle exec` and standalone execution.

---

### Task 1: Version Definition

Add a standard `VERSION` constant to the Norn namespace so it can be used by the gemspec and CLI.

**Files:**
- Create: `workspace/norn/lib/norn/version.rb`
- Modify: `workspace/norn/lib/norn.rb:1-5`

**Interfaces:**
- Produces: `Norn::VERSION` string

- [ ] **Step 1: Create version.rb**

Create `workspace/norn/lib/norn/version.rb` with content:
```ruby
module Norn
  VERSION = "0.0.1"
end
```

- [ ] **Step 2: Require version in lib/norn.rb**

Add `require_relative "norn/version"` at the top of `workspace/norn/lib/norn.rb`.

- [ ] **Step 3: Run existing RSpec tests to ensure no regressions**

Run: `bundle exec rspec` (from `workspace/norn`)
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add workspace/norn/lib/norn/version.rb workspace/norn/lib/norn.rb
git commit -m "feat: define Norn::VERSION and load it"
```

---

### Task 2: Create Gemspec and Update Gemfile

Define the gemspec with metadata and runtime/development dependencies, and configure the Gemfile to delegate to the gemspec.

**Files:**
- Create: `workspace/norn/norn.gemspec`
- Modify: `workspace/norn/Gemfile`

**Interfaces:**
- Produces: `norn.gemspec` and simplified `Gemfile`

- [ ] **Step 1: Create workspace/norn/norn.gemspec**

Create `workspace/norn/norn.gemspec` with the following content:
```ruby
require_relative "lib/norn/version"

Gem::Specification.new do |spec|
  spec.name          = "norn"
  spec.version       = Norn::VERSION
  spec.authors       = ["Petr Blaho"]
  spec.email         = ["petrblaho@gmail.com"]

  spec.summary       = "A pluggable LLM-driven agent development framework"
  spec.homepage      = "https://github.com/petrblaho/norn"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{\A(?:test|spec|features)/})
    end
  end
  spec.bindir        = "bin"
  spec.executables   = ["norn"]
  spec.require_paths = ["lib"]

  # Runtime Dependencies
  spec.add_dependency "dry-system", "~> 1.0"
  spec.add_dependency "dry-container", "~> 0.11"
  spec.add_dependency "dry-cli", "~> 1.1"
  spec.add_dependency "openai", "~> 0.69.0"
  spec.add_dependency "gemini-ai", "~> 4.3.0"
  spec.add_dependency "dry-configurable", "~> 1.2"
  spec.add_dependency "dry-schema", "~> 1.13"
  spec.add_dependency "dry-monads", "~> 1.6"
  spec.add_dependency "tty-markdown", "~> 0.7.0"
  spec.add_dependency "dotenv", "~> 3.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "reline"

  # Development/Test Dependencies
  spec.add_development_dependency "rspec", "~> 3.13"
end
```

- [ ] **Step 2: Update workspace/norn/Gemfile**

Replace the entire content of `workspace/norn/Gemfile` with:
```ruby
source "https://rubygems.org"

gemspec
```

- [ ] **Step 3: Run bundle install and verify Gemfile.lock**

Run: `bundle install` inside `workspace/norn`
Expected: Successfully installs/resolves dependencies using the gemspec and keeps the lockfile up to date.

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add workspace/norn/norn.gemspec workspace/norn/Gemfile workspace/norn/Gemfile.lock
git commit -m "feat: gemify norn by adding gemspec and delegating Gemfile"
```

---

### Task 3: Improve Bin Executable Loader

Make `bin/norn` robust to execution from external directories without requiring manual Bundler overrides.

**Files:**
- Modify: `workspace/norn/bin/norn:1-10`

**Interfaces:**
- Consumes: `ENV` and `File` helpers
- Produces: Intelligent Bundler/RubyGems bootstrapping in `bin/norn`

- [ ] **Step 1: Modify workspace/norn/bin/norn**

Change the initial lines of `workspace/norn/bin/norn` to:
```ruby
#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# If running directly from the cloned repository source without BUNDLE_GEMFILE being set,
# configure Bundler to use Norn's own Gemfile to ensure all dependencies are resolved.
if !defined?(Bundler) && File.exist?(File.expand_path("../Gemfile", __dir__))
  ENV["BUNDLE_GEMFILE"] = File.expand_path("../Gemfile", __dir__)
  begin
    require "bundler/setup"
  rescue LoadError
    # Bundler is not available, proceed anyway and rely on RubyGems
  end
elsif !defined?(Bundler)
  # When running as an installed gem, let RubyGems handle activation
else
  # Already in a Bundler environment (e.g., bundle exec norn from another project)
  # require bundler/setup is already done, or we do a graceful require if needed
  begin
    require "bundler/setup"
  rescue LoadError
  end
end

require "norn"
```

- [ ] **Step 2: Run tests inside the norn directory**

Run: `bundle exec rspec`
Expected: PASS

- [ ] **Step 3: Run the bin directly from the norn directory**

Run: `bin/norn --help` (without bundle exec)
Expected: Successfully loads and displays the help message without Dry::Monads LoadErrors.

- [ ] **Step 4: Commit**

```bash
git add workspace/norn/bin/norn
git commit -m "refactor: make bin/norn loader robust and bundler-aware"
```

---

### Task 4: Local Gem Build, Installation, and External Integration Verification

Verify we can build and install the gem locally, and integrate it into another project using the `:path` directive.

- [ ] **Step 1: Build the gem**

Run: `gem build norn.gemspec` inside `workspace/norn`
Expected: Output of the form `Successfully built RubyGem\n  Name: norn\n  Version: 0.0.1\n  File: norn-0.0.1.gem`

- [ ] **Step 2: Verify we can run it from anywhere by referencing bin/norn directly**

Run: `~/workspace/norn/bin/norn --help` (from home directory or another directory)
Expected: Successfully boots and displays help.

- [ ] **Step 3: Commit/Cleanup any built .gem files**

Add `.gem` to gitignore if not already present.
Run: `rm norn-0.0.1.gem` (to keep git clean)
```bash
git add workspace/norn/.gitignore
git commit -m "chore: ignore built .gem files"
```
