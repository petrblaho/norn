require "tty-prompt"

module Norn
  module UI
    class Gatekeeper
      def initialize(input: $stdin, output: $stdout)
        @input = input
        @output = output
        @prompt = TTY::Prompt.new(input: input, output: output)
      end

      def authorize_capabilities(tool_name, caps, args)
        @output.puts "\n⚠️  Security Escalation: Tool '#{tool_name}' requested unauthorized capabilities: #{caps.join(', ')}"
        @output.puts "Arguments: #{args.inspect}"

        choices = {
          "🔓 Yes, authorize these capabilities" => true,
          "🚫 No, deny authorization" => false
        }
        @prompt.select("Do you want to authorize this operation?", choices)
      end
    end
  end
end
