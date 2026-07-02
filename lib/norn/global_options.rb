module Norn
  module GlobalOptions
    @options = {}

    def self.register(name, type:, desc:, aliases: [], default: nil)
      @options[name.to_sym] = {
        type: type,
        desc: desc,
        aliases: aliases || [],
        default: default
      }
    end

    def self.registered_options
      @options
    end

    def self.clear!
      @options = {}
    end

    # Register the standard, built-in global options for Norn
    register :provider, 
             type: :string, 
             aliases: ["-p"], 
             desc: "LLM provider to use (openai, gemini)"

    register :debug, 
             type: :boolean, 
             aliases: ["-d"], 
             desc: "Enable debug logging and detailed contextual error outputs"
  end
end
