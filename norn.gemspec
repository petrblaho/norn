require_relative "lib/norn/version"

Gem::Specification.new do |spec|
  spec.name          = "norn"
  spec.version       = Norn::VERSION
  spec.authors       = ["Petr Blaho"]
  spec.email         = ["petrblaho@gmail.com"]

  spec.summary       = "A pluggable LLM-driven agent development framework"
  spec.homepage      = "https://github.com/petrblaho/norn"
  spec.license       = "GPL-3.0-only"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/petrblaho/norn"
  spec.metadata["bug_tracker_uri"] = "https://github.com/petrblaho/norn/issues"

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
