require_relative "client"

class GeminiPlugin < Norn::Plugin
  def self.plugin_name
    "gemini"
  end

  def on_boot(container)
    container.register("llm.gemini") do
      Norn::Plugins::Gemini::Client.new
    end
  end
end
