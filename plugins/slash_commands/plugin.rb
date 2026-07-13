module Norn
  module Plugins
    module SlashCommands
      class SlashCommand
        attr_reader :trigger, :description, :handler

        def initialize(trigger, description, &handler)
          @trigger = trigger.to_s.downcase.strip
          @description = description
          @handler = handler
        end

        def call(payload)
          @handler.call(payload)
        end
      end

      class Registry
        def initialize
          @commands = {}
        end

        def register(trigger, description, &handler)
          cmd = SlashCommand.new(trigger, description, &handler)
          @commands[cmd.trigger] = cmd
        end

        def resolve(trigger)
          @commands[trigger.to_s.downcase.strip]
        end

        def commands
          @commands.values
        end
      end

      class SlashCommandsPlugin < Norn::Plugin
        attr_reader :registry

        def self.plugin_name
          "slash_commands"
        end

        def initialize
          @registry = Registry.new
          register_builtins
          
          # Fire hook to let other plugins register custom slash commands
          Norn::PluginManager.trigger(:on_slash_commands_register, @registry)
        end

        def on_user_input(payload)
          text = payload[:text].to_s.strip
          
          if text.downcase == "/help"
            # Build help message dynamically from registered commands
            help_message = "\e[1;36mNorn Slash Commands:\e[0m\n"
            @registry.commands.each do |cmd|
              next unless cmd.trigger.start_with?("/")
              help_message << "  \e[1;32m%-15s\e[0m - #{cmd.description}\n" % cmd.trigger
            end
            return Dry::Monads::Success(payload.merge(action: :skip, output: help_message))
          end

          cmd = @registry.resolve(text)
          if cmd
            cmd.call(payload)
          else
            # Not a registered slash command, continue processing normally
            Dry::Monads::Success(payload)
          end
        end

        private

        def register_builtins
          @registry.register("/exit", "End the interactive session") do |payload|
            Dry::Monads::Success(payload.merge(action: :exit))
          end

          @registry.register("/quit", "End the interactive session") do |payload|
            Dry::Monads::Success(payload.merge(action: :exit))
          end

          @registry.register("exit", "End the interactive session (alias)") do |payload|
            Dry::Monads::Success(payload.merge(action: :exit))
          end

          @registry.register("quit", "End the interactive session (alias)") do |payload|
            Dry::Monads::Success(payload.merge(action: :exit))
          end

          @registry.register("/clear", "Reset conversational history and clear session statistics") do |payload|
            mode = payload[:mode]
            mode.messages.clear if mode && mode.messages
            
            begin
              session = Norn["session"]
              session.clear! if session
            rescue
            end

            clear_message = "\e[1;32m🧹 Session and conversation history cleared.\e[0m"
            Dry::Monads::Success(payload.merge(action: :skip, output: clear_message))
          end

          @registry.register("/reset", "Reset conversational history and clear session statistics") do |payload|
            mode = payload[:mode]
            mode.messages.clear if mode && mode.messages
            
            begin
              session = Norn["session"]
              session.clear! if session
            rescue
            end

            clear_message = "\e[1;32m🧹 Session and conversation history cleared.\e[0m"
            Dry::Monads::Success(payload.merge(action: :skip, output: clear_message))
          end
        end
      end
    end
  end
end
