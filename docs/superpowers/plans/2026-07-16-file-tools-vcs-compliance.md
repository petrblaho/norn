# File Tools VCS (.gitignore) Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate a high-speed, zero-dependency VCS ignore pattern matching engine into Norn's workspace file utilities to respect `.gitignore` rules and standard system folder exclusions during `glob` and `grep` searches.

**Architecture:** We build a standalone class `Norn::Plugins::FileTools::IgnoreFilter` that loads standard default directories (e.g., `.git`, `node_modules`, `vendor/bundle`) and parses any root-level `.gitignore` rules. Glob-style ignore patterns are translated into compiled Ruby `Regexp` objects for high-speed, concurrent-safe matching. This filter is instantiated once and injected into both the `glob` and `grep` tools to preemptively prune paths before reading files.

**Tech Stack:** Pure Ruby (standard library only), RSpec.

## Global Constraints

* Keep implementations DRY, YAGNI, and TDD-driven.
* Follow conventional commit guidelines with atomic, step-by-step commits.
* Handle encoding errors gracefully by parsing files with forced UTF-8 sanitization and `.scrub`.
* Avoid any third-party external gem additions.

---

## File Structure

1. `plugins/file_tools/path_helper.rb` — Implement `Norn::Plugins::FileTools::IgnoreFilter` within this file.
2. `plugins/file_tools/plugin.rb` — Integrate `IgnoreFilter` inside `glob` and `grep` tool definitions.
3. `spec/plugins/file_tools/ignore_spec.rb` — Create unit and integration specs.

---

### Task 1: Build the `IgnoreFilter` Class

**Files:**
- Create/Modify: `plugins/file_tools/path_helper.rb`

**Interfaces:**
- Produces: `Norn::Plugins::FileTools::IgnoreFilter` class exposing:
  * `initialize(root_path)` — parses defaults and `.gitignore` file.
  * `#ignored?(relative_path)` — returns `true` if the relative path matches any exclusion pattern.

- [ ] **Step 1: Declare the basic stub of `IgnoreFilter`**

Using `file_edit` or `file_write`, add the `IgnoreFilter` class structure to `plugins/file_tools/path_helper.rb`:

```ruby
module Norn
  module Plugins
    module FileTools
      class IgnoreFilter
        DEFAULT_EXCLUDES = [
          '.git', 'node_modules', 'vendor/bundle', 'tmp', 'log', 'coverage', '.sass-cache'
        ].freeze

        def initialize(root_path)
          @root = File.expand_path(root_path)
          @patterns = []
          DEFAULT_EXCLUDES.each { |pat| add_pattern(pat) }
          
          gitignore_path = File.join(@root, '.gitignore')
          if File.exist?(gitignore_path)
            File.readlines(gitignore_path, encoding: "utf-8").each do |line|
              cleaned = line.strip
              next if cleaned.empty? || cleaned.start_with?('#')
              add_pattern(cleaned)
            end
          end
        end

        def ignored?(relative_path)
          path = relative_path.to_s.sub(%r{^\/}, '')
          @patterns.any? { |re| re.match?(path) }
        end

        private

        def add_pattern(pat)
          is_dir = pat.end_with?('/')
          clean_pat = pat.sub(%r{^\/}, '').sub(%r{\/$}, '')

          escaped = Regexp.escape(clean_pat)
          escaped.gsub!('\\*\\*', '.*')
          escaped.gsub!('\\*', '[^/]*')
          escaped.gsub!('\\?', '[^/]')

          if is_dir
            regex_str = "^(#{escaped})(?:/.*)?$"
          else
            if clean_pat.include?('/')
              regex_str = "^(#{escaped})(?:/.*)?$"
            else
              regex_str = "(^|/)(#{escaped})($|/)"
            end
          end

          @patterns << Regexp.new(regex_str)
        rescue => e
          # Gracefully ignore malformed patterns
        end
      end
    end
  end
end
```

- [ ] **Step 2: Add `IgnoreFilter` to `plugins/file_tools/path_helper.rb`**

Use `file_edit` to append `IgnoreFilter` cleanly into `plugins/file_tools/path_helper.rb` without breaking `PathHelper.resolve_and_verify`.

- [ ] **Step 3: Run existing specs to verify no regressions**

Run: `bundle exec rspec`
Expected: All 266 existing tests pass.

- [ ] **Step 4: Commit task 1**

Run:
```bash
git add plugins/file_tools/path_helper.rb
git commit -m "feat(file_tools): implement IgnoreFilter pattern parser"
```

---

### Task 2: Integrate `IgnoreFilter` into `glob` and `grep` Tools

**Files:**
- Modify: `plugins/file_tools/plugin.rb`

**Interfaces:**
- Consumes: `Norn::Plugins::FileTools::IgnoreFilter`

- [ ] **Step 1: Instantiate the filter inside `on_tool_register`**

Modify `plugins/file_tools/plugin.rb` to build and cache a workspace-root-level `IgnoreFilter` instance inside `on_tool_register`:

```ruby
  def on_tool_register(registry)
    # Instantiate the workspace ignore filter once
    filter = Norn::Plugins::FileTools::IgnoreFilter.new(Norn.workspace_root)
```

- [ ] **Step 2: Apply the filter inside the `glob` tool block**

Modify the `glob` tool registration in `plugins/file_tools/plugin.rb` to reject paths matching the ignore filter:

```ruby
    # 4. glob
    registry.register(Norn::Tool.new(
      "glob",
      "Find files matching a glob pattern relative to the workspace root.",
      {
        type: "object",
        properties: {
          pattern: { type: "string", description: "The glob pattern (e.g. '**/*.rb' or 'lib/**/*.json')" }
        },
        required: ["pattern"]
      },
      required_capabilities: [:sys_read]
    ) { |args|
      root = File.expand_path(Norn.workspace_root)
      # Ensure the glob search runs safely inside root
      matches = Dir.glob(File.join(root, args[:pattern])).map do |abs_path|
        Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
      end
      matches.reject! { |rel_path| filter.ignored?(rel_path) }
      matches.any? ? matches.join("\n") : "No files matched."
    })
```

- [ ] **Step 3: Apply the filter inside the `grep` tool block**

Modify the `grep` tool registration in `plugins/file_tools/plugin.rb` to skip files matching the ignore filter before reading their contents:

```ruby
    # 5. grep
    registry.register(Norn::Tool.new(
      "grep",
      "Search for occurrences of a regular expression across files in the workspace.",
      {
        type: "object",
        properties: {
          pattern: { type: "string", description: "The regular expression to search for" },
          include: { type: "string", description: "Optional glob pattern to restrict searched files (e.g. '*.rb')" }
        },
        required: ["pattern"]
      },
      required_capabilities: [:sys_read]
    ) { |args|
      root = File.expand_path(Norn.workspace_root)
      pattern = Regexp.new(args[:pattern])
      glob_pattern = args[:include] || "**/*"

      results = []
      Dir.glob(File.join(root, glob_pattern)).each do |abs_path|
        relative_path = Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
        next if filter.ignored?(relative_path)
        next unless File.file?(abs_path)
        # Skip binary or very large files for performance
        next if File.size(abs_path) > 1_000_000

        begin
          File.readlines(abs_path, encoding: "utf-8").each_with_index do |line, idx|
            if line =~ pattern
              results << "#{relative_path}:#{idx + 1}: #{line.strip}"
            end
          end
        rescue => e
          # Ignore encoding/read errors silently
        end
      end

      results.any? ? results.join("\n") : "No matches found."
    })
```

- [ ] **Step 4: Run existing specs to guarantee zero compilation regressions**

Run: `bundle exec rspec`
Expected: All 266 existing tests pass.

- [ ] **Step 5: Commit task 2**

Run:
```bash
git add plugins/file_tools/plugin.rb
git commit -m "feat(file_tools): integrate IgnoreFilter into glob and grep tools"
```

---

### Task 3: Write Ignore boundary Specs

**Files:**
- Create: `spec/plugins/file_tools/ignore_spec.rb`

**Interfaces:**
- Consumes: `Norn::Plugins::FileTools::IgnoreFilter`

- [ ] **Step 1: Write comprehensive unit and integration specs**

Create the file `spec/plugins/file_tools/ignore_spec.rb` containing standard test coverage:

```ruby
require "spec_helper"
require "tmpdir"
require_relative "../../../plugins/file_tools/path_helper"

RSpec.describe Norn::Plugins::FileTools::IgnoreFilter do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  context "default excludes" do
    subject(:filter) { described_class.new(tmpdir) }

    it "always ignores .git directory" do
      expect(filter.ignored?(".git/config")).to be true
      expect(filter.ignored?("src/.git/config")).to be true
    end

    it "always ignores node_modules directory" do
      expect(filter.ignored?("node_modules/lodash/index.js")).to be true
      expect(filter.ignored?("src/node_modules/test.js")).to be true
    end

    it "always ignores tmp directory" do
      expect(filter.ignored?("tmp/cache/meta.json")).to be true
    end

    it "does not ignore normal source files" do
      expect(filter.ignored?("lib/norn.rb")).to be false
      expect(filter.ignored?("app/models/user.rb")).to be false
    end
  end

  context "parsing .gitignore patterns" do
    before do
      File.write(File.join(tmpdir, ".gitignore"), <<~GITIGNORE)
        # ignore all log files
        *.log

        # ignore nested coverage reports
        /coverage/

        # ignore build outputs specifically in the root dist
        /dist
      GITIGNORE
    end

    subject(:filter) { described_class.new(tmpdir) }

    it "correctly filters extension wildcards" do
      expect(filter.ignored?("development.log")).to be true
      expect(filter.ignored?("log/production.log")).to be true
      expect(filter.ignored?("src/log/debug.log")).to be true
      expect(filter.ignored?("logo.png")).to be false
    end

    it "correctly handles trailing slashes for directory matchers" do
      expect(filter.ignored?("coverage/index.html")).to be true
      expect(filter.ignored?("coverage/sub/details.json")).to be true
      expect(filter.ignored?("src/coverage/nested.html")).to be false
    end

    it "correctly anchors root-level files and folders" do
      expect(filter.ignored?("dist/bundle.js")).to be true
      expect(filter.ignored?("src/dist/bundle.js")).to be false
    end
  end
end
```

- [ ] **Step 2: Run the new specs and confirm they pass**

Run: `bundle exec rspec spec/plugins/file_tools/ignore_spec.rb`
Expected: 7 passing examples, 0 failures.

- [ ] **Step 3: Run the full rspec test suite to guarantee 100% compliance**

Run: `bundle exec rspec`
Expected: 273 examples, 0 failures.

- [ ] **Step 4: Commit task 3**

Run:
```bash
git add spec/plugins/file_tools/ignore_spec.rb
git commit -m "test(file_tools): add IgnoreFilter unit and integration specs"
```
