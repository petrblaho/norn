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

  def on_boot(container)
    require_relative "../../lib/norn/execution/subshell"
    
    unless container.key?("subprocess.shell")
      container.register("subprocess.shell") do
        Norn::Execution::Subshell.new
      end
    end
  end

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
      
      # 1. Run security validator on command
      Norn::Execution::CommandValidator.validate!(command)

      # 2. Trigger the before_subprocess_execute middleware hook
      payload = { command: command }
      before_result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
      
      if before_result.failure?
        next "Subprocess execution aborted: #{before_result.failure.message}"
      end
      
      sanitized_command = before_result.value![:command]

      # 3. Retrieve output streams
      output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout
      subshell = Norn::Container["subprocess.shell"]

      # 4. Record execution duration
      start_time = Time.now

      # 5. Execute process over state-preserving persistent shell
      outcome = subshell.execute(sanitized_command) do |stream_type, chunk|
        # Emit raw byte chunks to standard output notifications hook in real-time
        Norn::PluginManager.trigger(:on_subprocess_output, {
          stream: stream_type,
          chunk: chunk
        })

        if stream_type == :stderr
          output_stream.print "\e[1;31m#{chunk}\e[0m"
        else
          output_stream.print chunk
        end
      end

      duration = Time.now - start_time

      # 6. Trigger the after_subprocess_execute notification hook
      Norn::PluginManager.trigger(:after_subprocess_execute, {
        command: sanitized_command,
        exit_code: outcome.exit_code,
        duration: duration
      })

      # Return Outcome
      outcome.to_s
    end

    registry.register(execute_command_tool)
  end
end
