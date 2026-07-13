module Norn
  module Plugins
    module SlashCommands
      class SlashCommandsPlugin < Norn::Plugin
        def self.plugin_name
          "slash_commands"
        end

        def on_user_input(payload)
          text = payload[:text].to_s.strip
          mode = payload[:mode]

          case text.downcase
          when "exit", "quit", "/exit", "/quit"
            Dry::Monads::Success(payload.merge(action: :exit))
          when "/help"
            help_message = <<~HELP
              \e[1;36mNorn Slash Commands:\e[0m
                \e[1;32m/help\e[0m          - Show this help message
                \e[1;32m/exit\e[0m, \e[1;32m/quit\e[0m    - End the interactive session
                \e[1;32m/clear\e[0m, \e[1;32m/reset\e[0m  - Reset conversational history and clear session statistics
            HELP
            Dry::Monads::Success(payload.merge(action: :skip, output: help_message))
          when "/clear", "/reset"
            # Clear conversation history in the active mode
            if mode && mode.messages
              mode.messages.clear
            end

            # Clear session store if registered
            begin
              session = Norn["session"]
              session.clear! if session
            rescue => e
              # Session may not be registered in container, safe to ignore
            end

            clear_message = "\e[1;32m🧹 Session and conversation history cleared.\e[0m"
            Dry::Monads::Success(payload.merge(action: :skip, output: clear_message))
          else
            # Not a slash command, continue processing normally
            Dry::Monads::Success(payload)
          end
        end
      end
    end
  end
end
