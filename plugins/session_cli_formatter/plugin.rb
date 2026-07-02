module Norn
  module Plugins
    module SessionCliFormatter
      class SessionCliFormatterPlugin < Norn::Plugin
        def self.plugin_name
          "session_cli_formatter"
        end

        def on_render_response(payload)
          # Safely retrieve session stats from the rich rendering metadata
          stats = payload.dig(:ui_metadata, :session_stats)
          return payload unless stats

          total = stats[:total_tokens] || 0
          prompt = stats[:prompt_tokens] || 0
          completion = stats[:completion_tokens] || 0
          tools = (stats[:tool_calls] || []).size

          # Format a non-intrusive dim terminal footer using ANSI escape codes
          footer = "\n\n\e[90m(Tokens: #{total} [P: #{prompt} / C: #{completion}] | Tools: #{tools})\e[0m"

          # Create a merged payload to avoid in-place side effects
          payload.merge(text: payload[:text].to_s + footer)
        end
      end
    end
  end
end
