require "open3"
require "securerandom"
require "thread"

module Norn
  module Execution
    class Subshell
      def initialize(workspace_root: Norn.workspace_root)
        @workspace_root = workspace_root
        @lock = Mutex.new
        @started = false
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thr = nil
      end

      def started?
        @started
      end

      def start
        @lock.synchronize do
          return if @started

          shell_exec = ENV["SHELL"] || "bash"
          unless system("which #{shell_exec} >/dev/null 2>&1")
            shell_exec = "sh"
          end

          @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(shell_exec, chdir: @workspace_root)
          @started = true
        end
      end

      def execute(command, timeout: 60)
        start unless started?

        @lock.synchronize do
          token = "NORN_OUT_#{SecureRandom.hex(8)}"
          out_sentinel = "\n#{token}"

          # Stdin isolation using a bash group command block redirected to /dev/null.
          # Keeps command sequence sequential and prevents stdin swallowing.
          @stdin.puts("{ #{command} ; } </dev/null; echo \"#{token} $?\"")

          accumulated_stdout = ""
          accumulated_stderr = ""
          stdout_done = false
          stderr_done = false
          exit_code = 0

          # Non-leaking stream buffer state
          pending_yield = ""
          sentinel_length = out_sentinel.length

          loop do
            break if stdout_done && stderr_done

            ready = IO.select([@stdout, @stderr], nil, nil, timeout)
            if ready.nil?
              raise Timeout::Error, "Command execution timed out after #{timeout} seconds"
            end

            ready[0].each do |stream|
              if stream == @stdout
                begin
                  chunk = @stdout.read_nonblock(4096).force_encoding("UTF-8").scrub
                  accumulated_stdout << chunk
                  pending_yield << chunk

                  # We look for the sentinel in the pending buffer
                  if pending_yield.include?(token)
                    # Complete sentinel found
                    idx = pending_yield.index(out_sentinel) || pending_yield.index(token)
                    
                    # Yield anything before the start of the sentinel
                    if idx > 0
                      clean_chunk = pending_yield[0...idx]
                      yield :stdout, clean_chunk if block_given?
                    end

                    # Parse exit status
                    if match = accumulated_stdout.match(/#{token}\s+(\d+)/)
                      exit_code = match[1].to_i
                    end

                    stdout_done = true
                    stderr_done = true # Reachable once stdout sentinel hits
                  else
                    # Check if the trailing end matches a partial prefix of the out_sentinel
                    # Length to retain is up to (sentinel_length - 1) characters
                    partial_match_len = 0
                    (1...sentinel_length).each do |len|
                      prefix = out_sentinel[0, len]
                      if pending_yield.end_with?(prefix)
                        partial_match_len = len
                      end
                    end

                    if partial_match_len > 0
                      # Yield everything except the suspicious trailing suffix
                      yield_len = pending_yield.length - partial_match_len
                      if yield_len > 0
                        yield :stdout, pending_yield[0...yield_len] if block_given?
                        pending_yield = pending_yield[yield_len..-1]
                      end
                    else
                      # No trailing match, yield everything safely
                      yield :stdout, pending_yield if block_given?
                      pending_yield = ""
                    end
                  end
                rescue IO::WaitReadable
                rescue EOFError
                  stdout_done = true
                  stderr_done = true
                end
              elsif stream == @stderr
                begin
                  chunk = @stderr.read_nonblock(4096).force_encoding("UTF-8").scrub
                  accumulated_stderr << chunk
                  yield :stderr, chunk if block_given?
                rescue IO::WaitReadable
                rescue EOFError
                end
              end
            end
          end

          # Clean outcomes
          clean_stdout = accumulated_stdout.gsub(/\n?#{token}\s+\d+\n?/, "").strip
          clean_stderr = accumulated_stderr.strip

          Norn::Execution::Outcome.new(
            stdout: clean_stdout,
            stderr: clean_stderr,
            exit_code: exit_code
          )
        end
      rescue EOFError, Errno::EPIPE, Errno::ECONNRESET
        stop
        Norn::Execution::Outcome.new(
          stderr: "Persistent subshell terminated abruptly.",
          exit_code: 1
        )
      end

      def stop
        @lock.synchronize do
          return unless @started
          
          begin
            @stdin.puts("exit") if @stdin && !@stdin.closed?
            Process.kill("TERM", @wait_thr.pid) if @wait_thr && @wait_thr.alive?
          rescue
          ensure
            @stdin.close if @stdin && !@stdin.closed?
            @stdout.close if @stdout && !@stdout.closed?
            @stderr.close if @stderr && !@stderr.closed?
            @started = false
          end
        end
      end
    end
  end
end
