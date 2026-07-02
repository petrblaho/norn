require "dry/configurable"

module Norn
  class Config
    extend Dry::Configurable

    setting :llm_provider, default: "openai"
    setting :sandbox_info, default: "You are running in a secure sandboxed CLI environment."
    setting :openai_model, default: "gpt-4o-mini"
    setting :gemini_model, default: "gemini-3.5-flash"
    setting :temperature, default: 0.7
    setting :instructions_override, default: nil
    setting :custom_instructions, default: nil
  end
end
