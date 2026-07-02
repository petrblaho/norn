require_relative "client"

module Norn
  module Plugins
    module OpenAI
      class Plugin < Norn::Plugin
        def self.plugin_name
          "openai"
        end

        def on_boot(container)
          container.register("llm.openai") do
            Norn::Plugins::OpenAI::Client.new
          end
        end
      end
    end
  end
end
