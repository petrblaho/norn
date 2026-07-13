require "open3"

module Norn
  module Plugins
    module RSpec
      class RSpecTool < Norn::Tool
        def capabilities_for(args = {})
          [:sys_execute]
        end

        def dangerous?(args = {})
          false
        end
      end
    end
  end
end

class RSpecPlugin < Norn::Plugin
  def self.plugin_name
    "rspec"
  end

  RSPEC_SCHEMA = {
    type: "object",
    properties: {
      path: {
        type: "string",
        description: "The path to the spec file or directory to run (optional, e.g. 'spec/models/user_spec.rb')"
      },
      line_number: {
        type: "integer",
        description: "The specific line number to run (optional, e.g. 42)"
      },
      arguments: {
        type: "array",
        description: "Optional list of subsequent positional arguments and flags for rspec (e.g. ['--format', 'documentation', '-t', 'focus'])",
        items: { type: "string" }
      }
    }
  }

  def on_tool_register(registry)
    rspec_tool = Norn::Plugins::RSpec::RSpecTool.new(
      "rspec",
      "Run RSpec commands. Automatically runs with 'bundle exec' if a Gemfile is detected.",
      RSPEC_SCHEMA,
      system_instructions: "Use the 'rspec' tool to run tests and verify code correctness. You can run specific test files, line numbers, or folders."
    ) do |args, _context|
      root = File.expand_path(Norn::Container.config.root)
      gemfile_path = File.join(root, "Gemfile")

      cmd = []
      if File.exist?(gemfile_path)
        cmd += ["bundle", "exec"]
      end
      cmd << "rspec"

      if args[:path]
        path_arg = args[:path].to_s
        if args[:line_number]
          path_arg += ":#{args[:line_number]}"
        end
        cmd << path_arg
      end

      if args[:arguments]
        cmd += Array(args[:arguments]).map(&:to_s)
      end

      begin
        stdout, stderr, status = Open3.capture3(*cmd, chdir: root)
        stdout = stdout.to_s.dup.force_encoding("UTF-8").scrub
        stderr = stderr.to_s.dup.force_encoding("UTF-8").scrub

        if status.success?
          stdout.empty? ? "Tests passed successfully (no output)." : stdout
        else
          "RSpec execution failed:\n#{stderr}\n#{stdout}"
        end
      rescue => e
        "Failed to run RSpec command: #{e.message}"
      end
    end

    registry.register(rspec_tool)
  end
end
