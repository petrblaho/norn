require "dry/configurable"

module Norn
  class Config
    extend Dry::Configurable

    setting :llm_provider, default: "openai"
    setting :sandbox_info, default: "You are running in a secure sandboxed CLI environment."
    setting :openai_model, default: "gpt-4o-mini"
    setting :gemini_model, default: "gemini-3.5-flash"
    setting :temperature, default: 0.7
    setting :instructions, default: {
      clear: [],
      base: nil,
      prepend: [],
      append: []
    }
    setting :git_addon_enabled, default: false
    setting :git_addon_message, default: "Created with the use of LLM via Norn"
    setting :session_cli_format, default: "\e[2;36m(Tokens: %{total} [P: %{prompt} / C: %{completion}] | Tools: %{tools})\e[0m"
  end
end
