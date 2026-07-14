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
          normalized = trigger.to_s.strip.downcase

          # 1. Exact match first (highest precedence, handles non-slash commands or exact matches)
          return @commands[normalized] if @commands.key?(normalized)

          # 2. Extract first word
          first_word = normalized.split(/\s+/).first.to_s

          # 3. Only allow prefix/first-word match if the registered trigger starts with "/"
          if first_word.start_with?("/") && @commands.key?(first_word)
            return @commands[first_word]
          end

          nil
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
              trigger_part = "\e[1;32m%-15s\e[0m" % cmd.trigger
              help_message << "  #{trigger_part} - #{cmd.description}\n"
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

          @registry.register("/tools", "List all registered tools, their required capabilities, and descriptions") do |payload|
            tools = Norn::ToolRegistry.registered_tools
            message = "\e[1;36m🔧 Registered Norn Tools:\e[0m\n"
            if tools.empty?
              message << "  No tools registered.\n"
            else
              tools.each do |tool|
                caps = tool.required_capabilities.map(&:to_s).join(", ")
                danger_str = tool.dangerous? ? " \e[1;31m[DANGEROUS]\e[0m" : ""
                name_part = "\e[1;32m%-15s\e[0m" % tool.name
                message << "  #{name_part} - #{tool.description} (Caps: \e[33m#{caps}\e[0m)#{danger_str}\n"
              end
            end
            Dry::Monads::Success(payload.merge(action: :skip, output: message))
          end

          @registry.register("/session", "Display token usage statistics and tool call metrics for the current session") do |payload|
            begin
              session = Norn["session"]
              if session
                stats = session.stats
                tool_calls_count = stats[:tool_calls].is_a?(Array) ? stats[:tool_calls].size : stats[:tool_calls]
                message = "\e[1;36m📊 Current Session Stats:\e[0m\n" \
                          "  Prompt Tokens:     #{stats[:prompt_tokens]}\n" \
                          "  Completion Tokens: #{stats[:completion_tokens]}\n" \
                          "  Total Tokens:      #{stats[:total_tokens]}\n" \
                          "  Tool Calls:        #{tool_calls_count}\n"
              else
                message = "\e[1;31mSession tracking is not active.\e[0m"
              end
            rescue => e
              message = "\e[1;31mFailed to retrieve session statistics: #{e.message}\e[0m"
            end
            Dry::Monads::Success(payload.merge(action: :skip, output: message))
          end
        end
      end
    end
  end
end
