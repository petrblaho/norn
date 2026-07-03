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

          format_string = Norn::Config.config.session_cli_format
          
          # Check if using the default format string
          if format_string == "\e[2;36m(Tokens: %{total} [P: %{prompt} / C: %{completion}] | Tools: %{tools})\e[0m"
            parts = []
            parts << "Tokens: #{total} [P: #{prompt} / C: #{completion}]" if total > 0
            parts << "Tools: #{tools}" if tools > 0
            return payload if parts.empty?
            
            formatted_stats = "\e[2;36m(#{parts.join(' | ')})\e[0m"
          else
            # Custom format string
            formatted_stats = format_string % {
              total: total,
              prompt: prompt,
              completion: completion,
              tools: tools
            }
          end

          # Format a non-intrusive dim terminal footer using ANSI escape codes
          footer = "\n\n#{formatted_stats}"

          # Create a merged payload to avoid in-place side effects
          payload.merge(text: payload[:text].to_s + footer)
        end
      end
    end
  end
end
