require "tty-prompt"

class PromptUserPlugin < Norn::Plugin
  def self.plugin_name
    "prompt_user"
  end

  def on_tool_register(registry)
    registry.register(Norn::Tool.new(
      "prompt_user",
      "Prompt the user for input, confirmations, or choices dynamically via interactive CLI widgets.",
      {
        type: "object",
        properties: {
          type: {
            type: "string",
            description: "The type of interactive control to render.",
            enum: ["input", "confirm", "select", "multi_select"]
          },
          question: {
            type: "string",
            description: "The question, prompt text, or instruction to display to the user."
          },
          choices: {
            type: "array",
            description: "A list of options/choices. Required only for 'select' and 'multi_select' types.",
            items: { type: "string" }
          },
          allow_custom: {
            type: "boolean",
            description: "If true, appends a 'Custom' write-in option to single select choices. If selected, the user is prompted for inline text input in a single turn."
          },
          custom_prompt: {
            type: "string",
            description: "Optional custom prompt text to display when asking the user for their custom write-in input."
          },
          default_value: {
            type: "string",
            description: "An optional default value to return if the user presses enter immediately or if the session is non-interactive."
          }
        },
        required: ["type", "question"]
      },
      required_capabilities: [:sys_read],
      system_instructions: "If a user instruction is ambiguous, or if you need to present multiple options/choices, call the 'prompt_user' tool to obtain structured feedback or selections. To offer a write-in/custom text selection alongside predefined choices in a single turn, set 'allow_custom' to true."
    ) do |args, context|
      # 1. Non-interactive Fallback Safeguard
      unless context && context.interactive?
        if args[:default_value]
          next "Non-interactive session fallback: #{args[:default_value]}"
        else
          raise "Error: Interactive prompting is not supported in non-interactive sessions."
        end
      end

      # 2. Instantiate TTY::Prompt bound to the REPL's standard streams passed in context
      prompt = TTY::Prompt.new(input: context.input, output: context.output)

      case args[:type]
      when "confirm"
        answer = prompt.yes?(args[:question], default: args[:default_value] == "true")
        answer ? "yes" : "no"

      when "select"
        raise "Error: 'choices' parameter is required for select prompt." if args[:choices].nil? || args[:choices].empty?
        
        choices = args[:choices].map(&:to_s)
        allow_custom = args[:allow_custom] == true || args[:allow_custom] == "true"
        custom_option = "Custom (type your own...)"
        
        choices << custom_option if allow_custom

        # Append help text directly to the question so it remains permanently visible during keypresses
        question_with_help = "#{args[:question]} \e[36m(Use arrow keys, Enter to select)\e[0m"
        selected = prompt.select(question_with_help, choices)

        final_selected_val = if allow_custom && selected == custom_option
                               # Prompt inline for custom input in a single turn
                               prompt.ask(args[:custom_prompt] || "Please type your custom value:")
                             else
                               selected
                             end

        # Re-render the complete selection permanently to the console scrollback for visual history
        context.output.puts "\e[32m●\e[0m Selected choice:"
        choices.each do |choice|
          is_selected = (selected == choice)
          status_symbol = is_selected ? "‣" : " "
          status_color = is_selected ? "\e[32m" : "\e[90m" # Green for selected, dim grey for unselected
          text_color = is_selected ? "\e[1;32m" : "\e[0m"
          context.output.puts "  #{status_color}#{status_symbol} #{text_color}#{choice}\e[0m"
        end
        if allow_custom && selected == custom_option
          context.output.puts "    \e[90m↳ Inputted value:\e[0m \e[1;32m#{final_selected_val}\e[0m"
        end
        context.output.puts

        final_selected_val

      when "multi_select"
        raise "Error: 'choices' parameter is required for multi_select prompt." if args[:choices].nil? || args[:choices].empty?
        
        # Append help text directly to the question so it remains permanently visible during keypresses
        question_with_help = "#{args[:question]} \e[36m(Press Space to toggle options, Enter to submit)\e[0m"
        answers = prompt.multi_select(question_with_help, args[:choices])
        selected_array = answers.map(&:to_s)

        # Re-render the complete checklist selection permanently to the console scrollback for visual history
        context.output.puts "\e[32m●\e[0m Selected choices:"
        args[:choices].each do |choice|
          is_selected = selected_array.include?(choice.to_s)
          status_symbol = is_selected ? "⬢" : "⬡"
          status_color = is_selected ? "\e[32m" : "\e[90m" # Green for selected, dim grey for unselected
          text_color = is_selected ? "\e[1;32m" : "\e[0m"
          context.output.puts "  #{status_color}#{status_symbol} #{text_color}#{choice}\e[0m"
        end
        context.output.puts

        answers.join(", ")

      when "input"
        prompt.ask(args[:question], default: args[:default_value])
      else
        raise "Error: Unsupported prompt type '#{args[:type]}'."
      end
    end)
  end
end
