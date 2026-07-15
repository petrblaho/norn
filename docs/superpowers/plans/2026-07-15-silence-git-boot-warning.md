# Silence Git Boot Warning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Silence the noisy `fatal: not a git repository` warning on stderr during CLI boot by introducing a robust git-detection check with a pure-Ruby glob fallback inside the gemspec, and locked with an integration spec.

**Architecture:** We will modify `norn.gemspec` to dynamically inspect if Norn's directory is a Git worktree. If it is, we find files via `git ls-files` with silenced stderr redirect (`2>#{File::NULL}`); if not (e.g. packaged or run from release zip), we fall back to standard `Dir.glob` for code, plugins, configurations, and documentation. We will verify the fix using a high-fidelity integration test that runs the binary from a clean non-git temporary directory.

**Tech Stack:** Pure Ruby, Bundler, RSpec, Open3.

## Global Constraints

- Must run cleanly on Ruby versions >= 3.0.0.
- No new external gem dependencies.
- Suppressed warning must not hide actual application boot failures.

---

### Task 1: Update Gemspec File Discovery

**Files:**
- Modify: `norn.gemspec:18-22`

**Interfaces:**
- Produces: `spec.files` array containing source, libraries, bin directories, plugins, docs, and top-level configuration metadata.

- [ ] **Step 1: Modify `norn.gemspec` to use Approach 1 with fallback**

Replace lines 18-22 in `norn.gemspec` with the following:

```ruby
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    # Check if we are inside a Git worktree safely without printing anything to stderr
    is_git_repo = File.exist?(".git") || system("git rev-parse --is-inside-work-tree >#{File::NULL} 2>&1")

    if is_git_repo
      `git ls-files -z 2>#{File::NULL}`.split("\x0").reject do |f|
        f.match(%r{\A(?:test|spec|features)/})
      end
    else
      # Fallback files listing for packaging/evaluating in non-git environments
      files = Dir["{bin,lib,plugins,docs}/**/*"].select { |f| File.file?(f) }
      files += Dir["*.md"]
      files += ["Gemfile", "Gemfile.lock", "LICENSE", "norn.gemspec"]
      files.uniq
    end
  end
```

- [ ] **Step 2: Run current RSpec suite to ensure nothing is broken**

Run: `bundle exec rspec`
Expected: ALL tests pass.

- [ ] **Step 3: Commit gemspec change**

```bash
git add norn.gemspec
git commit -m "chore(gemspec): silence git warning and fallback in non-git contexts"
```

---

### Task 2: Add Non-Git Environment Integration Spec

**Files:**
- Modify: `spec/norn/bin_norn_spec.rb`

**Interfaces:**
- Consumes: `bin/norn` script entry point.

- [ ] **Step 1: Write integration spec verifying silence in a non-git directory**

Modify `spec/norn/bin_norn_spec.rb` to add a new `it` block inside the `RSpec.describe "bin/norn executable"` block:

```ruby
  it "silences git stderr warnings when booting outside of a git repository" do
    require "tmpdir"
    require "fileutils"

    Dir.mktmpdir do |temp_dir|
      # Copy minimum required boot assets to the temp directory
      FileUtils.cp_r(File.expand_path("../../bin", __dir__), temp_dir)
      FileUtils.cp_r(File.expand_path("../../lib", __dir__), temp_dir)
      FileUtils.cp_r(File.expand_path("../../plugins", __dir__), temp_dir)
      FileUtils.cp(File.expand_path("../../Gemfile", __dir__), temp_dir)
      FileUtils.cp(File.expand_path("../../Gemfile.lock", __dir__), temp_dir)
      FileUtils.cp(File.expand_path("../../norn.gemspec", __dir__), temp_dir)

      # Run the executable inside the temp directory (which lacks any parent .git)
      temp_bin_path = File.join(temp_dir, "bin", "norn")
      _stdout, stderr, _status = Open3.capture3(temp_bin_path)

      # Assert that git complains are completely silenced
      expect(stderr).not_to include("fatal: not a git repository")
      expect(stderr).not_to include("Stopping at filesystem boundary")
    end
  end
```

- [ ] **Step 2: Run newly added test to verify it passes**

Run: `bundle exec rspec spec/norn/bin_norn_spec.rb`
Expected: PASS (2 examples, 0 failures)

- [ ] **Step 3: Run the entire test suite**

Run: `bundle exec rspec`
Expected: PASS (237 examples, 0 failures)

- [ ] **Step 4: Commit the test**

```bash
git add spec/norn/bin_norn_spec.rb
git commit -m "test(bin): add integration test verifying silence of git warning during boot"
```
