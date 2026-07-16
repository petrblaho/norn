# Design Spec: VCS (.gitignore) Compliance and Dir Skip-Filters in File Tools

* **Date**: 2026-07-16
* **Status**: Approved / Brainstormed
* **Authors**: Petr Blaho & Norn AI
* **Target Card**: [Implement VCS (.gitignore) Compliance and Dir Skip-Filters in File Tools](https://app.basecamp.com/5717936/buckets/48052540/card_tables/cards/10094241533)

---

## 1. Context & Business Case

To operate reliably and rapidly on enterprise-scale repositories, Norn's core search utilities—specifically the `glob` and `grep` tools—must avoid scanning redundant, generated, or transient system files. Reading deeply nested folders like `node_modules`, standard compiled packages, dependencies inside `vendor/bundle`, or large local log files creates massive CPU overhead, exhausts token constraints, and floods the AI agent's context window with completely irrelevant noise.

By introducing a zero-dependency, fast VCS `.gitignore` matching engine that parses local workspace rule definitions and merges them with robust, hardcoded fallbacks, we guarantee high-speed, relevant search actions across all development environments.

---

## 2. Component Architecture

We isolate the VCS filter from the tool invocation wrapper. The new component lives in the `Norn::Plugins::FileTools` namespace:

```
                            ┌────────────────────────────────┐
                            │      Norn::ToolRegistry        │
                            └───────────────┬────────────────┘
                                            │ (Invokes)
                                            ▼
                            ┌────────────────────────────────┐
                            │    FileToolsPlugin (glob/grep) │
                            └───────────────┬────────────────┘
                                            │ (Filters paths via)
                                            ▼
                            ┌────────────────────────────────┐
                            │      PathHelper::IgnoreFilter  │
                            └────────────────────────────────┘
```

### 2.1 Class Contract: `Norn::Plugins::FileTools::IgnoreFilter`
* **File**: `plugins/file_tools/path_helper.rb`
* **Responsibilities**:
  * On initialization, load a series of standard fallback exclusions.
  * Attempt to read and parse `.gitignore` rules from the workspace root if it exists.
  * Expose an efficient, thread-safe `#ignored?(relative_path)` predicate method.
  * Translate gitignore glob syntax rules (wildcards `*`, directory specifiers `tmp/`, etc.) into compiled regular expressions.

---

## 3. Pattern Compilation Logic

To map `.gitignore` patterns to Ruby's `Regexp` engine safely and accurately, the compiler adheres to these rules:

1. **Comments and Empty Lines**: Skip lines starting with `#` or empty lines.
2. **Directory Specifiers**: Patterns ending with `/` (e.g. `tmp/`) match the directory itself and any files/folders nested inside.
3. **Anchored Patterns**: If a pattern contains a slash `/` in the middle or starts with a slash `/` (excluding a trailing slash), it is anchored relative to the workspace root.
4. **General Matches**: Patterns without any inline slashes (e.g. `*.log`, `node_modules`) match anywhere in the file hierarchy (recursively).
5. **Glob Translation**:
   - `**` is converted to `.*` (match across directories).
   - `*` is converted to `[^/]*` (match within a single directory boundary).
   - `?` is converted to `[^/]`.

---

## 4. Integration Specifications

### 4.1 `glob` Integration
The `glob` tool queries `Dir.glob` across the workspace. We filter results before compiling the response:

```ruby
filter = Norn::Plugins::FileTools::IgnoreFilter.new(Norn.workspace_root)
# ...
matches = Dir.glob(File.join(root, args[:pattern])).map do |abs_path|
  Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
end
matches.reject! { |rel_path| filter.ignored?(rel_path) }
```

### 4.2 `grep` Integration
The `grep` tool recursively traverses the workspace. We reject paths at the traversal level before reading files to avoid high disk/CPU overhead:

```ruby
filter = Norn::Plugins::FileTools::IgnoreFilter.new(Norn.workspace_root)
# ...
Dir.glob(File.join(root, glob_pattern)).each do |abs_path|
  relative_path = Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
  next if filter.ignored?(relative_path)
  next unless File.file?(abs_path)
  # (Proceed to read and parse patterns)
```

---

## 5. Security and performance Gaps Resolved

1. **Encoding Integrity**: When parsing `.gitignore`, we read files with `encoding: "utf-8"` and ignore any malformed patterns gracefully to prevent runtime crashes on developer machines.
2. **Path Traversal Shield**: The workspace absolute path expansion checks (`resolve_and_verify`) remain fully active and run prior to any file interaction.
3. **Fast Fallbacks**: In the absence of a `.gitignore` file, the filter defaults to robust built-in excludes: `.git`, `node_modules`, `vendor/bundle`, `tmp`, `log`, `coverage`.

---

## 6. Testing Strategy

1. **Regex Compilation Specs**: Verify individual translations (e.g., `tmp/` ignores `tmp/a.txt` and `tmp/sub/b.txt`; `*.log` matches `a.log` and `src/b.log`).
2. **Workspace Simulation Specs**: Create a mock workspace directory containing nested files (some matching ignores, some matching valid files). Assert that running `glob` and `grep` over this mock directory strictly excludes ignored paths.
3. **Missing Config Resilience**: Assert that the system remains stable and utilizes fallback excludes if the mock workspace completely lacks a `.gitignore`.
