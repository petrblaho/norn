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

      # Construct array safely to completely prevent shell injection vulnerabilities (e.g. avoid ';' or '|' chaining)
      cmd = ["git", subcmd] + extra_args

      begin
        root = File.expand_path(Norn.workspace_root)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: root)

        if status.success?
          stdout.empty? ? "Command executed successfully (no output)." : stdout
        else
          "Error executing git #{subcmd}: #{stderr}\n#{stdout}"
        end
      rescue => e
        "Failed to run git command: #{e.message}"
      end
    end

    registry.register(git_tool)
  end
end
