module Norn
  module Plugins
    module SessionTrackTools
      class SessionTrackToolsPlugin < Norn::Plugin
        def self.plugin_name
          "session_track_tools"
        end

        # Hook: record tool calls in the active session
        def after_tool_call(tool_name, args, result, error)
          session = Norn["session"] rescue nil
          return unless session

          session.record_tool_call(
            tool_name: tool_name,
            arguments: args,
            result: result,
            error: error
          )
        end
      end
    end
  end
end
