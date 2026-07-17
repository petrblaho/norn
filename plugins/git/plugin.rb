require "open3"

module Norn
  module Plugins
    module Git
      class GitTool < Norn::Tool
        def capabilities_for(args = {})
          subcommand = args[:subcommand].to_s.downcase
          case subcommand
          when "status", "diff", "log", "show", "branch"
            [:vcs_read, :sys_read]
          when "add", "commit", "checkout", "reset", "rm", "merge", "rebase"
            [:vcs_write, :sys_write]
          when "pull", "push", "fetch", "clone"
            [:vcs_write, :net_egress]
          else
            # Unrecognized subcommands default to high security execute permission
            [:sys_execute]
          end
        end

        def dangerous?(args = {})
          subcommand = args[:subcommand].to_s.downcase
          extra_args = Array(args[:arguments]).map(&:to_s)

          case subcommand
          when "commit", "push", "add"
            true
          when "checkout"
            # checkout with file paths or force flags is dangerous as it can discard modifications
            extra_args.any? { |a| a == "." || a == "--" || a.start_with?("-f") }
          when "reset"
            # reset --hard is highly destructive
            extra_args.any? { |a| a.include?("hard") || a.include?("purge") }
          else
            false
          end
        end

        def session_approval_label(args = {})
          subcommand = args[:subcommand]
          if subcommand
            "Approve 'git #{subcommand}' for the rest of this session"
          else
            "Approve 'git' for the rest of this session"
          end
        end

        def session_approval_pattern(args = {})
          pattern = { tool_name: "git" }
          pattern[:subcommand] = args[:subcommand].to_s.downcase if args[:subcommand]
          pattern
        end

        def session_approved?(session, args)
          return false if session.nil?

          subcommand = args[:subcommand].to_s.downcase
          approvals = session.get(:session_approvals) || []

          approvals.any? do |app|
            app[:tool_name] == "git" && app[:subcommand] == subcommand
          end
        end

        def allow_session_danger?
          false
        end
      end
    end
  end
end

class GitPlugin < Norn::Plugin
  def self.plugin_name
    "git"
  end

  def self.declare_hooks(manager)
    manager.declare_hook :before_git_commit, desc: "ROP middleware. Allows inspecting/mutating git commit arguments (like message)."
  end

  GIT_SCHEMA = {
    type: "object",
    properties: {
      subcommand: {
        type: "string",
        description: "The primary Git subcommand to run",
        enum: ["status", "diff", "log", "show", "add", "commit", "checkout", "branch", "reset", "pull", "push", "fetch"]
      },
      arguments: {
        type: "array",
        description: "Optional list of subsequent positional arguments and flags (e.g. ['-m', 'refactor: error handling'] or ['.'])",
        items: { type: "string" }
      }
    },
    required: ["subcommand"]
  }

  def on_tool_register(registry)
    git_tool = Norn::Plugins::Git::GitTool.new(
      "git",
      "Interact with the git repository (status, diff, commit, checkout, branch, pull, push, etc.).",
      GIT_SCHEMA,
      system_instructions: "Use the 'git' tool to examine version control status (git status, git diff) or commit your work step-by-step. Keep commits atomic and precise."
    ) do |args, context|
      subcmd = args[:subcommand]
      extra_args = Array(args[:arguments]).map(&:to_s)

      if subcmd == "commit"
        payload = { subcommand: subcmd, arguments: extra_args }
        middleware_result = Norn::PluginManager.trigger_middleware(:before_git_commit, payload)
        if middleware_result.success?
          extra_args = middleware_result.value![:arguments]
        end
      end

      require "shellwords"
      cmd = ["git", subcmd] + extra_args
      command_str = Shellwords.join(cmd)

      # Trigger the before_subprocess_execute middleware hook
      payload = { command: command_str }
      before_result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
      sanitized_command = before_result.success? ? before_result.value![:command] : command_str

      begin
        root = File.expand_path(Norn.workspace_root)
        if Norn::Container.key?("subprocess.shell")
          subshell = Norn::Container["subprocess.shell"]
          output_stream = (context && context.respond_to?(:output)) ? context.output : $stdout
          
          outcome = subshell.execute(sanitized_command) do |stream_type, chunk|
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
          
          if outcome.success?
            outcome.stdout.empty? ? "Command executed successfully (no output)." : outcome.stdout
          else
            "Error executing git #{subcmd}:\n#{outcome.stderr}\n#{outcome.stdout}"
          end
        else
          require "shellwords"
          stdout, stderr, status = Open3.capture3(*Shellwords.split(sanitized_command), chdir: root)

          if status.success?
            stdout.empty? ? "Command executed successfully (no output)." : stdout
          else
            "Error executing git #{subcmd}: #{stderr}\n#{stdout}"
          end
        end
      rescue => e
        "Failed to run git command: #{e.message}"
      end
    end

    registry.register(git_tool)
  end
end
