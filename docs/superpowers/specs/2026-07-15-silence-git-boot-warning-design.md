# Design Spec: Silence Git Boot Warning Outside Git Repository Context

* **Date**: 2026-07-15
* **Status**: Approved
* **Target Card**: Card 10097656973 (Bug: Stderr git warning during boot ("fatal: not a git repository"))

---

## 1. Context & Root Cause Analysis

When booting Norn in environments that lack a Git repository (e.g. Docker containers with stripped `.git`, production servers, or `.zip` downloads), executing the CLI prints a noisy and confusing warning to `stderr`:

```
fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
```

### Path of Execution During Boot
1. Running the `norn` CLI maps to `bin/norn`.
2. `bin/norn` detects the development environment and requires `"bundler/setup"`.
3. Bundler loads Norn's `Gemfile`.
4. Norn's `Gemfile` evaluates the `gemspec` directive.
5. This loads and executes the Ruby code in `norn.gemspec`.
6. Inside `norn.gemspec`, `spec.files` is defined using a backtick shell subprocess:
   ```ruby
   spec.files = Dir.chdir(File.expand_path(__dir__)) do
     `git ls-files -z`.split("\x0").reject do |f|
       f.match(%r{\A(?:test|spec|features)/})
     end
   end
   ```
7. Because the active environment is not a git repository, the shell execution fails and leaks the warning directly to the parent process's `stderr` stream.

---

## 2. Proposed Design: Git-Aware Fallback Discovery

To solve this cleanly, we will make the file discovery logic in `norn.gemspec` context-aware. 

1. **Verify Git Context**: We check if we are currently inside a Git repository.
2. **Clean Execution**: If inside a repository, we query files using Git, cleanly routing any unexpected stderr to the null device (`File::NULL`).
3. **Pure-Ruby Fallback**: If we are not inside a Git repository, we fall back to a standard filesystem glob search to locate the binary, library files, core plugins, and documentation.

### norn.gemspec Implementation Layout
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

---

## 3. Testing and Verification Strategy

To guarantee that this issue never recurs, we will add a high-fidelity integration test that simulates execution outside of a git repository.

### `spec/norn/bin_norn_spec.rb` Integration Test
We will create a test that:
1. Allocates a temporary directory.
2. Copies Norn's executable, libraries, plugins, configuration, and gemspec files into this directory (with no `.git` metadata).
3. Executes the duplicated `bin/norn` binary.
4. Asserts that the stderr is free of git warnings and boot proceeds cleanly.

---

## 4. Spec Self-Review Check
* **Placeholder Scan**: No "TBD" or "TODO" sections. All directory mappings are concrete.
* **Internal Consistency**: Directory fallbacks correctly align with the directory layout defined in the main `README.md`.
* **Scope Check**: Highly targeted. Strictly fixes boot warning without affecting core CLI behavior.
* **Ambiguity Check**: Redirecting stderr to `File::NULL` is completely cross-platform (handling Windows `NUL` as well as Unix `/dev/null` gracefully).
