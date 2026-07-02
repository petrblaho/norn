# Implementation Plan: Norn Chatbot MVP

## Phase 1: Bootstrapping & Directory Setup
We will set up the foundational workspace directory structure and define our dependencies in the `Gemfile`.

1. **Initialize `Gemfile`**:
   * Add core dependencies: `dry-system`, `dry-container`, `dry-cli`, `tty-prompt` (or standard `readline` for input), and `ruby-openai` (for the OpenAI plugin).
2. **Scaffold Directory Layout**:
   * Create the `bin/` directory and `bin/norn` entry point.
   * Create `lib/norn/` for core classes.
   * Create `lib/plugins/` for the plugin subsystem.

---

## Phase 2: Dependency Injection & System Booting (`dry-system`)
We will configure `dry-system` to manage the lifecycle of Norn. This ensures all components, including plugins, can register dependencies into a central container.

1. **Establish the Container (`lib/norn/container.rb`)**:
   * Define the `Norn::Container` class inheriting from `Dry::System::Container`.
   * Configure load paths to automatically load files inside `lib/norn`.
2. **Hook Registry (`lib/norn/plugin_manager.rb`)**:
   * Implement a lightweight, thread-safe Event/Hook Bus.
   * Support subscribing block handlers to named events (e.g., `:on_boot`, `:on_cli_register`, `:before_llm_call`, `:after_llm_call`).
   * Support publishing/triggering events which yield data to all subscribed handlers.

---

## Phase 3: Plugin Loading Mechanism
We will design Norn to load plugins dynamically from `lib/plugins/` at boot, enabling total freedom for hook registrations.

1. **Plugin Loader (`lib/norn/plugin_loader.rb`)**:
   * Scan the `lib/plugins/` directory for subdirectories.
   * Dynamically require each plugin’s `plugin.rb` file.
2. **Registering hooks inside plugins**:
   * Provide a clean DSL or method for plugins to register subscriptions:
     ```ruby
     Norn::PluginManager.subscribe(:on_boot) do
       # Initialization logic
     end
     ```

---

## Phase 4: Core CLI & REPL (`dry-cli`)
We will define the command-line router and the primary REPL interactive loop.

1. **CLI Commands Manager (`lib/norn/cli.rb`)**:
   * Set up `Dry::CLI` as the main router.
   * Define a basic command registry.
   * Fire a hook (`:on_cli_register`) yielding the CLI registry so plugins can register custom commands if they wish.
2. **Chat Command (`lib/norn/cli/chat.rb`)**:
   * Define the `norn chat` command.
   * Upon invocation, it initializes the core **Chatbot REPL**.
3. **Core Chatbot REPL (`lib/norn/chatbot.rb`)**:
   * Keeps track of the unified conversation history: `[{ role: "user", content: "..." }, { role: "assistant", content: "..." }]`.
   * Accepts user inputs in a loop until the user types `exit` or `quit`.
   * When sending a prompt:
     1. Triggers the `:before_llm_call` hook (allows plugins to mutate/append messages or system instructions).
     2. Resolves the active stateless LLM client from the Container.
     3. Executes the call with the conversation history.
     4. Appends the response to the conversation history.
     5. Triggers the `:after_llm_call` hook (allows plugins to inspect responses, calculate costs, or run side-effects).

---

## Phase 5: The OpenAI Plugin (First proof-of-concept)
We will build our first plugin to prove the stateless LLM translator concept.

1. **Plugin Entry (`lib/plugins/openai/plugin.rb`)**:
   * Subscribes to `:on_boot` to register the OpenAI client wrapper into the `Norn::Container` under `"llm.openai"`.
2. **Stateless OpenAI Client (`lib/plugins/openai/client.rb`)**:
   * Wraps the `ruby-openai` gem.
   * Exposes a simple `#call(messages)` method that translates Norn's message history to OpenAI's schema, executes the API call, and translates the response back to Norn's unified schema.

---

## Phase 6: Executable & Environment Config
We will glue everything together in the executable.

1. **Executable (`bin/norn`)**:
   * Requires `bundler/setup`.
   * Boots the `Norn::Container`.
   * Dispatches command routing via `Dry::CLI`.
2. **API Key Setup**:
   * The OpenAI plugin will expect the standard `OPENAI_API_KEY` environment variable.

---

## Verification & Self-Testing Loop
Once implemented, we will verify the MVP by:
1. Setting an `OPENAI_API_KEY` environment variable.
2. Running `ruby -Ilib bin/norn chat` (or using `bundle exec bin/norn chat`).
3. Confirming we get a functional response from OpenAI in a stateless translator fashion.
4. Attempting to switch LLMs or verifying that the hooks are fired in order during execution.
