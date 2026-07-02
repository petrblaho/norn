require "dry/configurable"

module Norn
  class Config
    extend Dry::Configurable

    setting :llm_provider, default: "openai"
    setting :sandbox_info, default: "You are running in a secure sandboxed CLI environment."
  end
end
