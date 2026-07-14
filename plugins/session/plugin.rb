require_relative "session"

module Norn
  module Plugins
    module Session
      class SessionPlugin < Norn::Plugin
        def self.plugin_name
          "session"
        end

        def on_boot(container)
          # Initialize and memoize our Session singleton
          @session ||= Norn::Session.new

          unless container.key?("session")
            container.register("session") do
              @session
            end
          end
        end

        def on_tool_register(registry)
          registry.register(Norn::Tool.new(
            "get_session_stats",
            "Retrieve active session metrics, including token usage, tool call history, and session-level command approvals.",
            {
              type: "object",
              properties: {}
            },
            system_instructions: "Use this tool to inspect token usage, tool counts, active session-level command approvals, and conversational stats of the current active session."
          ) do |_args, _context|
            begin
              Norn["session"].to_h.to_json
            rescue => e
              "Error retrieving session stats: #{e.message}"
            end
          end)
        end

        # Hook: before calling LLM, we can record the messages
        def before_llm_call(messages)
          return unless active_session

          # Clear current history in session and sync it with active messages to maintain up-to-date conversation state
          active_session.set(:history, [])
          messages.each do |msg|
            active_session.record_message(role: msg[:role].to_s, content: msg[:content].to_s)
          end
        end

        # Hook: after LLM call completes, record the final response message
        def after_llm_call(response_text)
          return unless active_session

          active_session.record_message(role: "assistant", content: response_text.to_s)
        end

        # Hook: contribute session data to the ROP rendering pipeline's rich metadata
        def on_render_response(payload)
          return payload unless active_session

          payload[:ui_metadata] ||= {}
          payload[:ui_metadata][:session_stats] = active_session.to_h
          payload
        end

        private

        def active_session
          Norn["session"]
        rescue => e
          nil
        end
      end
    end
  end
end
