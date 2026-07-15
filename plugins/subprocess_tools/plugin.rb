require "dry/monads"

class SubprocessToolsPlugin < Norn::Plugin
  include Dry::Monads[:result]

  def self.plugin_name
    "subprocess_tools"
  end

  SUBPROCESS_SCHEMA = {
    type: "object",
    properties: {
      command: {
        type: "string",
        description: "The raw shell command string to execute in the workspace root."
      }
    },
    required: ["command"]
  }

  def on_tool_register(registry)
    execute_command_tool = Norn::Tool.new(
      "execute_command",
      "Executes raw shell or command-line instructions safely in the project workspace root.",
      SUBPROCESS_SCHEMA,
      required_capabilities: [:sys_execute],
      system_instructions: "Use this tool to run workspace-local processes, tests, compiles, or checkups.",
      dangerous: true
    ) do |args, context|
      command = args[:command].to_s.strip
      
      # 1. Run strict security validation checks
      Norn::Execution::CommandValidator.validate!(command)

      # 2. Extract output stream from calling mode context if available, otherwise fallback to stdout
      output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout

      # 3. Execute process with concurrent stream readers
      outcome = Norn::UI::SubprocessRunner.run(command) do |stream_type, chunk|
        if stream_type == :stderr
          # Print error streams in red / warning colors
          output_stream.print "\e[1;31m#{chunk}\e[0m"
        else
          output_stream.print chunk
        end
      end

      # Return the string representation of the outcome back to the caller
      outcome.to_s
    end

    registry.register(execute_command_tool)
  end
end
