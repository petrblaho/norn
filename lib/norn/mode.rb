require "dry/monads"
require "reline"
require_relative "diff_helper"

module Norn
  class Mode
    include Dry::Monads[:result]

    attr_reader :input, :output, :messages

    ABSTRACT_METHODS = [:interactive?, :allowed_capabilities, :instructions, :banner_name]

    def initialize(input: $stdin, output: $stdout)
      @input = input
      @output = output
      @messages = []
    end

    def start(prompt = nil)
      raise NotImplementedError, "#{self.class} must implement #start"
    end

    def interactive?
      raise NotImplementedError, "#{self.class} must implement #interactive?"
    end

    def allowed_capabilities
      raise NotImplementedError, "#{self.class} must implement #allowed_capabilities"
    end

    def instructions
      raise NotImplementedError, "#{self.class} must implement #instructions"
    end

    def banner_name
      raise NotImplementedError, "#{self.class} must implement #banner_name"
    end

    # The master orchestrator for any Mode (handles both single-turn tasks and multi-turn REPL loops)
    def start(prompt = nil)
      system_prompt = compile_system_prompt

      # A. Non-Interactive Single-Turn execution (e.g. Task Mode)
      unless interactive?
        if prompt.nil? || prompt.strip.empty?
          return Failure(Norn::FailurePayload.new(
            Norn::UsageError.new("A prompt or task is required for #{banner_name}."),
            { mode: self.class.name }
          ))
        end

        @output.puts "#{banner_name} initialized."
        @output.puts "Using active provider: #{Norn.config.llm_provider}\n\n"

        @messages << { role: "user", content: prompt }
        
        turn_result = execute_turn(system_prompt)
        return turn_result if turn_result.failure?

        return Success(@messages)
      end

      # B. Interactive Multi-Turn REPL execution (e.g. Chat or Dev Mode)
      @output.puts "#{banner_name} initialized."
      @output.puts "Using active provider: #{Norn.config.llm_provider}"
      @output.puts "Type 'exit' or 'quit' to end the session.\n\n"

      first_turn = true

      loop do
        if first_turn && prompt
          line = prompt
          @output.print "You: "
          @output.puts line
          first_turn = false
        else
          line = get_input("You: ")
        end
        break if line.nil?

        line = line.strip
        break if ["exit", "quit"].include?(line.downcase)
        next if line.empty?

        # Append user message
        @messages << { role: "user", content: line }

        # Execute the turn (processes LLM requests, handles tool calls recursively)
        turn_result = execute_turn(system_prompt)
        if turn_result.failure?
          # Output the error message but continue the REPL loop
          @output.puts "Error: #{turn_result.failure.message}"
        end

        @output.puts
      end

      @output.puts "Goodbye!"
      Success(nil)
    end

    # Secure gatekeeper to execute registered tools safely under capability & danger policies
    def execute_tool(tool_name, args)
      # Ensure arguments are fully symbolized for consistent key access throughout the gatekeeper and diff engine
      args = symbolize_keys(args)

      tool = Norn::ToolRegistry.resolve(tool_name)
      if tool.nil?
        return Success("Error: Tool '#{tool_name}' not found in registry.")
      end

      # 1. Capability Authorization Check
      required_caps = tool.capabilities_for(args)
      missing_caps = required_caps - allowed_capabilities

      unless missing_caps.empty?
        # Handle capability escalation
        if interactive?
          @output.puts "\n⚠️  Security Escalation: Tool '#{tool_name}' requested unauthorized capabilities: #{missing_caps.join(', ')}"
          @output.puts "Arguments: #{args.inspect}"
          @output.print "Do you want to authorize this operation? [y/N]: "
          
          response = @input.gets.to_s.strip.downcase
          if ["y", "yes"].include?(response)
            @output.puts "🔓 Operation authorized by user."
            allowed_capabilities.concat(missing_caps)
          else
            @output.puts "🚫 Operation blocked by user."
            return Failure(Norn::FailurePayload.new(
              Norn::ToolError.new("Authorization denied by user to run tool '#{tool_name}' requiring capabilities: #{missing_caps.join(', ')}."),
              { tool: tool_name, missing_capabilities: missing_caps }
            ))
          end
        else
          # Non-interactive block-by-default on capability violations
          @output.puts "\n❌ Security Block: Tool '#{tool_name}' requires #{missing_caps.join(', ')} which is unauthorized in non-interactive mode."
          return Failure(Norn::FailurePayload.new(
            Norn::ToolError.new("Security violation: Unauthorized capabilities requested in non-interactive mode: #{missing_caps.join(', ')}."),
            { tool: tool_name, missing_capabilities: missing_caps, mode: self.class.name }
          ))
        end
      end

      # 2. In-Flight Interactive Danger Guards
      if tool.dangerous?(args) && interactive?
        if ["file_write", "file_edit"].include?(tool_name)
          # Interactive File Diff Previewer
          begin
            root = File.expand_path(Norn::Container.config.root)
            abs_path = File.expand_path(args[:path], root)
            raise SecurityError, "Path traversal attempt detected" unless abs_path.start_with?(root)

            old_content = File.exist?(abs_path) ? File.read(abs_path) : ""
            new_content = if tool_name == "file_write"
                            args[:content].to_s
                          else
                            old_content.sub(args[:old_string].to_s, args[:new_string].to_s)
                          end

            @output.puts "\n📝 Proposed changes to \e[1;32m#{args[:path]}\e[0m:"
            @output.puts Norn::DiffHelper.color_diff(old_content, new_content)
            @output.print "Apply these changes? [Y/n]: "
          rescue => e
            return Failure(Norn::FailurePayload.new(e, { tool: tool_name, args: args }))
          end
        else
          # Generic Command Execution Guard
          @output.puts "\n⚠️  Warning: Norn wants to execute a potentially dangerous command: '#{tool_name}'"
          @output.puts "Arguments: #{args.inspect}"
          @output.print "Execute this command? [Y/n]: "
        end

        response = @input.gets.to_s.strip.downcase
        # Empty input defaults to Approval (represented by capitalized Y in prompt [Y/n])
        if response.empty? || ["y", "yes"].include?(response)
          @output.puts "🔓 Action authorized."
        else
          @output.puts "🚫 Action aborted by user."
          return Failure(Norn::FailurePayload.new(
            Norn::ToolError.new("Action aborted by user."),
            { tool: tool_name, args: args }
          ))
        end
      end

      # 3. Proceed to safe execution, passing self as context
      begin
        Success(tool.call(args, self).to_s)
      rescue => e
        Success("Error executing tool '#{tool_name}': #{e.message}")
      end
    end

    # Dynamically compiles the system prompt by aggregating sandbox configs, 
    # mode-level instructions, and LLM directives registered by all authorized tools.
    def compile_system_prompt
      system_parts = []
      
      # 1. Sandbox Info (Strictly environment metadata)
      system_parts << Norn.config.sandbox_info if Norn.config.sandbox_info && !Norn.config.sandbox_info.empty?
      
      # 2. Base Instructions (Mode-specific, but fully overridable from config)
      base_instructions = Norn.config.instructions_override || instructions
      system_parts << base_instructions if base_instructions && !base_instructions.empty?

      # Gather tools authorized under the active mode's permitted capabilities
      authorized_tools = Norn::ToolRegistry.registered_tools.select do |tool|
        (tool.required_capabilities - allowed_capabilities).empty?
      end

      # Retrieve and format all plugin/tool-defined prompt directions
      tool_directives = authorized_tools.map(&:system_instructions).compact
      if tool_directives.any?
        compiled_directives = "TOOL EXECUTION DIRECTIVES:\n" + tool_directives.map { |d| "• #{d}" }.join("\n")
        system_parts << compiled_directives
      end

      # 3. Custom instructions (Appended rules/constraints)
      if Norn.config.custom_instructions && !Norn.config.custom_instructions.strip.empty?
        system_parts << Norn.config.custom_instructions
      end

      system_parts.reject(&:empty?).join("\n\n")
    end

    private

    # Runs a single conversational turn, processing any tool calls generated by the LLM
    # until a final text response is produced. Returns Success(response_text) or Failure(payload).
    def execute_turn(system_prompt)
      loop do
        active_messages = @messages.dup
        unless system_prompt.empty?
          active_messages.unshift({ role: :system, content: system_prompt })
        end

        Norn::PluginManager.trigger(:before_llm_call, active_messages)

        provider = Norn.config.llm_provider
        client = begin
                   Norn::Container["llm.#{provider}"]
                 rescue => e
                   return Failure(Norn::FailurePayload.new(
                     Norn::ProviderError.new("LLM provider '#{provider}' is not registered."),
                     { provider: provider, step: :resolve_client }
                   ))
                 end

        # Only expose tools whose capabilities are fully authorized in the pre-flight list
        authorized_tools = Norn::ToolRegistry.registered_tools.select do |tool|
          (tool.required_capabilities - allowed_capabilities).empty?
        end

        # Execute the LLM call with a nice spinner
        response_result = with_spinner("Thinking...") do
          if authorized_tools.any?
            client.call(active_messages, tools: authorized_tools)
          else
            client.call(active_messages)
          end
        end

        return response_result if response_result.failure?

        response = response_result.value!

        if response.is_a?(Hash) && response[:type] == :tool_call
          # Append assistant's tool call request to history, preserving raw Gemini parts if present
          msg = {
            role: "assistant",
            content: nil,
            tool_calls: response[:calls]
          }
          msg[:parts] = response[:parts] if response[:parts]
          @messages << msg

          response[:calls].each do |call|
            tool_name = call[:name]
            args = call[:arguments]
            id = call[:id]

            @output.puts "🔧 Running #{tool_name} with arguments: #{args.inspect}..."

            exec_result = execute_tool(tool_name, args)
            return exec_result if exec_result.failure?

            result_str = exec_result.value!

            # Append tool execution result back to history
            @messages << {
              role: "tool",
              tool_call_id: id,
              name: tool_name,
              content: result_str
            }
          end

          # Keep looping to let the LLM process the tool results
          next
        else
          # Extract text response
          response_text = response.is_a?(Hash) ? response[:content] : response.to_s

          # Run the response text through our sequential ROP rendering middleware pipeline
          rendered_response = response_text.dup
          middleware_result = Norn::PluginManager.trigger_middleware(:on_render_response, { text: rendered_response })
          if middleware_result.success?
            rendered_response = middleware_result.value![:text]
          else
            return middleware_result
          end

          @output.puts "\e[1;34mNorn:\e[0m"
          @output.puts rendered_response

          msg = {
            role: "assistant",
            content: response_text,
            parts: response.is_a?(Hash) ? response[:parts] : nil
          }.compact
          @messages << msg

          Norn::PluginManager.trigger(:after_llm_call, response_text)
          return Success(response_text) # Complete the turn!
        end
      end
    end

    def with_spinner(label)
      # Only spin if output is a TTY and not in a non-interactive environment/test with mock streams
      if !@output.respond_to?(:tty?) || !@output.tty?
        return yield
      end

      chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
      delay = 0.08
      thread = Thread.new do
        Thread.current[:stop] = false
        i = 0
        until Thread.current[:stop]
          @output.print "\r\e[K\e[1;36m#{chars[i % chars.size]}\e[0m #{label}"
          @output.flush
          sleep delay
          i += 1
        end
      end

      begin
        yield
      ensure
        if thread
          thread[:stop] = true
          thread.join rescue nil
          @output.print "\r\e[K" # Clear the line when done
          @output.flush
        end
      end
    end

    def get_input(prompt)
      if @input == $stdin
        Reline.readline(prompt, true)
      else
        @output.print prompt
        line = @input.gets
        @output.puts line if line
        line
      end
    end

    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
      end
    end
  end
end
