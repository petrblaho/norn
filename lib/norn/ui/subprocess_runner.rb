require "open3"

module Norn
  module UI
    class SubprocessRunner
      def self.run(command, workspace_root: Norn.workspace_root)
        accumulated_stdout = ""
        accumulated_stderr = ""

        Open3.popen3(command, chdir: workspace_root) do |stdin, stdout, stderr, wait_thr|
          stdin.close

          stdout_thread = Thread.new do
            begin
              while (chunk = stdout.readpartial(4096))
                accumulated_stdout << chunk
                yield :stdout, chunk if block_given?
              end
            rescue EOFError
              # Stream ended
            end
          end

          stderr_thread = Thread.new do
            begin
              while (chunk = stderr.readpartial(4096))
                accumulated_stderr << chunk
                yield :stderr, chunk if block_given?
              end
            rescue EOFError
              # Stream ended
            end
          end

          stdout_thread.join
          stderr_thread.join

          exit_code = wait_thr.value.exitstatus

          Norn::Execution::Outcome.new(
            stdout: accumulated_stdout,
            stderr: accumulated_stderr,
            exit_code: exit_code
          )
        end
      rescue Errno::ENOENT => e
        Norn::Execution::Outcome.new(
          stderr: "Failed to spawn process: command not found - #{e.message}",
          exit_code: 127
        )
      end
    end
  end
end
