require "tty-markdown"
require "dry/monads"

class TTYMarkdownPlugin < Norn::Plugin
  include Dry::Monads[:result]

  def self.plugin_name
    "tty_markdown"
  end

  # Declare that this rendering hook is optional and can fail-safe/recover
  def self.hook_policies
    { on_render_response: :recover }
  end

  def on_render_response(payload)
    return Success(payload) unless payload.is_a?(Hash) && payload[:text]

    begin
      # Parse the markdown using TTY::Markdown with custom copy-paste-friendly overrides nested under 'override:'
      rendered = TTY::Markdown.parse(payload[:text],
        symbols: {
          override: {
            bullet: "•",
            bar: " ", # Use space instead of "│" to keep copy-paste clean
            quote: "“"
          }
        },
        mode: 256 # Supports the 256-color palette
      )
      Success(payload.merge(text: rendered))
    rescue => e
      # Return a Failure monad carrying full error context to the pipeline (which Norn will log as a warning and recover)
      Failure(Norn::FailurePayload.new(
        Norn::ToolError.new("Markdown rendering failed: #{e.message}"),
        { plugin: "tty_markdown", original_error: e }
      ))
    end
  end
end
