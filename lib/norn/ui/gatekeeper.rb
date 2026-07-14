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

      def authorize_danger(tool, args)
        tool_name = tool.name
        
        if ["file_write", "file_edit"].include?(tool_name)
          # Interactive File Diff Previewer
          begin
            root = File.expand_path(Norn.workspace_root)
            abs_path = File.expand_path(args[:path].to_s, root)
            unless abs_path == root || abs_path.start_with?(root + File::SEPARATOR)
              raise SecurityError, "Path traversal attempt detected"
            end

            old_content = File.exist?(abs_path) ? File.read(abs_path) : ""
            new_content = if tool_name == "file_write"
                            args[:content].to_s
                          else
                            old_content.sub(args[:old_string].to_s, args[:new_string].to_s)
                          end

            @output.puts "\n📝 Proposed changes to \e[1;32m#{args[:path]}\e[0m:"
            @output.puts Norn::DiffHelper.color_diff(old_content, new_content)
          rescue => e
            @output.puts "Diff Generation Error: #{e.message}"
            return false
          end
        else
          # Generic Danger Warning
          @output.puts "\n⚠️  Warning: Norn wants to execute a potentially dangerous command: '#{tool_name}'"
          @output.puts "Arguments: #{args.inspect}"
        end

        choices = {
          "🔓 Yes, proceed" => true,
          "🚫 No, abort/review" => false
        }
        @prompt.select("Execute this action?", choices)
      end
    end
  end
end
