# Norn

Norn is a **stateless, extensible, dynamic software engineering agent** written in pure Ruby. 

> 🔮 **Note:** This project is entirely **vibecoded**—built in a continuous, high-speed, flow-based collaboration between a human developer and AI coding assistants.

Norn is designed for reliability, dependency stability, and ease of installation. It avoids common agent challenges (like complex dependency trees, native compilation failures, and fragile global states) by relying entirely on Ruby's robust standard library and stable pure-Ruby gems.

---

## 🚀 Key Features

* **Zero Native C-Dependencies:** Friction-free installations without system compiler or environment ABI mismatches.
* **Railway-Oriented Programming (ROP):** Every service, configuration loader, and LLM call returns a monadic `Success` or `Failure` result via `dry-monads`, mitigating runtime crashes and enabling clear diagnostic context reporting.
* **Capability-Based Sandboxing:** Granular permission system (`sys:read`, `sys:write`, `sys:execute`, etc.). Pre-flight tool pruning prevents token waste, and an in-flight gatekeeper handles dynamic runtime prompts (Y/N) or automatic non-interactive blocks.
* **In-Flight Guards & Diff Previews:** Significant file operations in interactive modes trigger a line-aligned, ANSI-colored console diff preview before prompting for user permission.
* **In-Memory Secret Scrubbing:** A multi-layered scanner recursively scrubs and redacts API keys, bearer tokens, or user secrets to prevent credentials from ever leaking to log traces, CLI outputs, or debug files.
* **Decoupled Plugin Architecture:** Add custom UI renderers, custom modes, or LLM providers seamlessly as self-contained classes.

---

## 📁 Project Directory Layout

```
├── ARCHITECTURE.md          # Primary technical specifications & design manual
├── ONBOARDING.md            # Detailed senior handoff and onboarding guide
├── GAPS.md                  # Registry of backlog gaps and refactoring needs
├── bin/
│   └── norn                 # Executable entrypoint and argument normalizer
├── lib/
│   └── norn/
│       ├── cli.rb           # Dynamic CLI command generator (dry-cli)
│       ├── config.rb        # Config settings definitions (dry-configurable)
│       ├── container.rb     # Dependency injection registry (dry-system)
│       ├── mode.rb          # Abstract operational base mode
│       ├── plugin.rb        # Abstract plugin base class
│       └── tool.rb          # Unified tool schema and capability evaluation
├── plugins/
│   ├── file_tools/          # Filesystem reads, writes, edits, and searches
│   ├── prompt_user/         # Interactive CLI prompt widgets (tty-prompt)
│   ├── tty_markdown/        # Markdown console rendering middleware
│   ├── openai/              # OpenAI LLM client adapter
│   └── gemini/              # Gemini LLM client adapter
└── spec/                    # RSpec unit tests
```

---

## 🛠️ Quick Start

### 1. Prerequisites
Ensure you have Ruby installed. Install dependencies via Bundler:
```bash
bundle install
```

### 2. Configure Environment Variables
Create a local `.env` file in the project root:
```env
OPENAI_API_KEY=your-openai-api-key
GEMINI_API_KEY=your-gemini-api-key
NORN_PROVIDER=openai  # or gemini
```

### 3. Start Chat Mode (Read-Only Code Exploration)
Use Chat mode to safely explore and query your codebase. It has strictly restricted read-only permissions (`[:sys_read, :vcs_read]`):
```bash
./bin/norn chat "Search for all ruby files and explain how Container works"
```

### 4. Start Dev Mode (Full Interactive Pairing)
Use Dev Mode for write-enabled pairing. Safe in-flight danger guards and diff prompts will protect your repository:
```bash
./bin/norn dev
```
Prompt: *`Write a new ruby file under lib/norn/version.rb containing VERSION = "1.0.0"`* (Watch the diff engine present the proposed file creation before asking for approval!).

### 5. Start Task Mode (Autonomous Execution)
Run single-turn autonomous tasks (blocks on capability escalations by default to prevent unintended actions):
```bash
./bin/norn task "Summarize ARCHITECTURE.md"
```

---

## 🧪 Testing

We follow test-driven isolation practices. Reset hooks clear the dynamic plugin registry and dependency container before each test. Run the test suite:

```bash
bundle exec rspec
```

---

## 📘 Reference Documentation

For deeper details, consult our internal engineering books:
* **`ARCHITECTURE.md`**: Design philosophy, ROP pipelines, and dynamic hook reduction models.
* **`ONBOARDING.md`**: Guide to architecture flows, core files, and developer quick-starts.
* **`GAPS.md`**: The current development backlog, containing known gaps (such as MCP integration status and hardcoded configurations).
