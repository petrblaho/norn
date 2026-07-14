require "tty-prompt"
require "dry/monads"

module Norn
  module UI
    class Gatekeeper
      include Dry::Monads[:result]

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

      def show_fallback_menu(tool_name, args)
        choices = {
          "Skip this execution (allow agent to continue without this result)" => :skip,
          "Edit command arguments inline (freeform feedback)" => :edit,
          "Abort the active agent session completely" => :abort
        }
        @prompt.select("\nOperation Aborted. What would you like to do next?", choices)
      end

      def refine_arguments(tool, args, user_feedback, client)
        prompt = <<~PROMPT
          You are a precise tool parameter refiner. Your task is to update the parameters of a tool based on user feedback.

          Tool Name: #{tool.name}
          Tool Description: #{tool.description}
          Tool Schema: #{tool.parameters.to_json}

          Original Parameters: #{args.to_json}

          User Feedback: #{user_feedback}

          Analyze the user's feedback, apply requested changes to the original parameters, and ensure they conform to the tool schema.
          Output ONLY a raw, valid JSON object containing the updated parameters.
          Do NOT wrap output in markdown codeblocks. Do NOT add extra explanation or prose.
        PROMPT

        response_result = client.call([{ role: "user", content: prompt }])
        return response_result if response_result.failure?

        response = response_result.value!
        response_text = response.is_a?(Hash) ? response[:content] : response.to_s

        # Robust cleaning of markdown backticks if LLM ignores instruction
        cleaned_text = response_text.gsub(/```json|```/, "").strip

        begin
          parsed = JSON.parse(cleaned_text)
          Success(symbolize_keys(parsed))
        rescue => e
          Failure("Invalid JSON returned by refiner LLM: #{e.message}")
        end
      end

      private

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        end
      end
    end
  end
end
