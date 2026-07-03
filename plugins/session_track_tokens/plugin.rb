module Norn
  module Plugins
    module SessionTrackTokens
      class SessionTrackTokensPlugin < Norn::Plugin
        def self.plugin_name
          "session_track_tokens"
        end

        # Hook: record token usage in the active session
        def after_llm_response(response, provider, model)
          session = Norn["session"] rescue nil
          return unless session
          return unless response.is_a?(Hash) && response[:usage]

          usage = response[:usage]
          session.record_tokens(
            prompt: usage[:prompt_tokens] || 0,
            completion: usage[:completion_tokens] || 0,
            provider: provider,
            model: model
          )
        end
      end
    end
  end
end
