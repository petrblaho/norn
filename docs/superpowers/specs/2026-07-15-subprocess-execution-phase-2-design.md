# Design Spec: Subprocess Execution - Phase 2: The Hook Network (Persistent Shell & Events)

* **Date**: 2026-07-15
* **Status**: Proposed / Brainstormed
* **Authors**: Petr Blaho & Norn AI
* **Target Card**: [Subprocess Execution - Phase 2: The Hook Network (Persistent Shell & Events)](https://app.basecamp.com/5717936/buckets/48052540/card_tables/cards/10097083524)

---

## 1. Context & Business Case

In Phase 1 of our Subprocess Execution roadmap, we introduced basic local execution via the `execute_command` tool. However, this implementation is stateless: every command spawns a brand new, short-lived subprocess (`Open3.popen3`). 

This creates several operational limitations:
1. **Loss of Environment & Directory State**: Running `cd lib/` in one turn does not affect subsequent commands, as they boot in fresh processes back at the workspace root. Tool execution cannot preserve virtualenvs, custom environment variable exports, or rbenv/nvm context.
2. **Buffering & Streaming Delays**: Streams are read by individual threads that join only when the process exits. This prevents real-time line-by-line or byte-by-byte streaming to interactive coordinator interfaces.

Phase 2 upgrades the execution engine to be **fully stateful** and introduces a reactive **Execution Hook Network** to enable downstream plugins—like our upcoming Phase 3 A2A Agent Bridge—to hook into subprocess stdout/stderr streams in real-time.

---

## 2. Component Boundaries & Architecture

We will separate our persistent shell and event routing into three highly focused parts:

```
                            ┌────────────────────────────────────┐
                            │      SubprocessToolsPlugin         │
                            └─────────────────┬──────────────────┘
                                              │ (on_tool_register)
                                              ▼
                            ┌────────────────────────────────────┐
                            │    execute_command Tool definition │
                            └─────────────────┬──────────────────┘
                                              │
                                              ▼ (uses)
                            ┌────────────────────────────────────┐
                            │      Norn::Execution::Subshell     │
                            └─────────┬────────────────┬─────────┘
                                      │                │
                        (writes command)               │ (reads stderr/stdout via IO.select)
                                      ▼                ▼
                            ┌──────────────────┐  ┌──────────────────┐
                            │    stdin pipe    │  │  stdout/stderr   │
                            └──────────────────┘  └──────────────────┘
                                      │                │
                                      ▼                ▼
                            ┌────────────────────────────────────┐
                            │      Persistent Bash Subprocess     │
                            └────────────────────────────────────┘
```

### 2.1 Component: `Norn::Execution::Subshell`
* **File**: `lib/norn/execution/subshell.rb`
* **Responsibilities**:
  * Launch and maintain a long-lived `/bin/bash` (falling back to `/bin/sh`) process.
  * Hold open pipes to `stdin`, `stdout`, and `stderr`.
  * Protect stream reads and writes with a thread-safe `Mutex` lock to prevent command interleaving.
  * Expose an on-demand `#start` initialization routine.
  * Expose a `#execute(command) { |stream_type, chunk| ... }` pipeline.
  * Expose a `#stop` shutdown method to terminate the background PID cleanly.

### 2.2 Container Integration
We register the subshell in Norn's global container under the key `"subprocess.shell"` inside `SubprocessToolsPlugin#on_boot`:
```ruby
def on_boot(container)
  container.register("subprocess.shell") do
    Norn::Execution::Subshell.new
  end
end
```
To optimize resource consumption, `Norn::Execution::Subshell` is initialized lazily and does not spawn the `/bin/bash` process until its first execution call.

### 2.3 Subprocess Hook Definitions
We will extend `Norn::PluginManager` inside `register_core_hooks!` to declare the following event hooks:
* `:before_subprocess_execute` — ROP middleware. Allows commands to be scanned, audited, or blocked.
* `:on_subprocess_output` — Notification. Emits raw string chunks read from the stream in real-time.
* `:after_subprocess_execute` — Notification. Emits the final exit code and execution duration.

---

## 3. The Sentinel-Token Protocol

Because a background shell stays open indefinitely, its output streams will never hit EOF during standard execution. Attempting to do a standard blocking read on `stdout` or `stderr` will hang the Norn session forever. 

To determine exactly when a command has finished executing and extract its exit status, we introduce a **Sentinel-Token Protocol**:

```
                       SENTINEL-TOKEN WRITE PROTOCOL
                       
  stdin.puts(command)
  stdin.puts("echo \"\"")
  stdin.puts("echo \"__NORN_OUT_SENTINEL_abc123 $?\"")
  stdin.puts("echo \"__NORN_ERR_SENTINEL_abc123\" >&2")
  
                       SENTINEL-TOKEN READ PIPELINE
                       
   Read stdout stream ──► Yields chunks ──► Stops at "__NORN_OUT_SENTINEL_abc123 <status>"
   Read stderr stream ──► Yields chunks ──► Stops at "__NORN_ERR_SENTINEL_abc123"
```

1. **Unique Token Generation**: For every invocation, we generate a randomized alphanumeric string (`token = "NORN_SENTINEL_#{SecureRandom.hex(8)}"`).
2. **Synchronized Sentinel Writing**: We write the raw user command to the subshell's `stdin`, immediately followed by:
   * An empty echo statement `echo ""` (to handle commands that lack trailing newlines).
   * A stdout sentinel `echo "#{token}_OUT $?"` (printing the exit code of the user command).
   * A stderr sentinel `echo "#{token}_ERR" >&2` (written directly to stderr).
3. **Synchronized Reading**: We read from `stdout` and `stderr` concurrently, parsing and yielding chunks, and stop reading once the matching sentinel string is detected in **both** streams.
4. **Outcome Extraction**: We parse the exit status from the `stdout` sentinel line, strip the sentinel lines from our accumulated stdout/stderr buffers, and return a clean `Norn::Execution::Outcome`.

---

## 4. Non-Blocking Stream Multiplexing (`IO.select`)

To stream characters continuously without blockages, we run an `IO.select` multiplexing loop. This eliminates the need for separate threads per execution turn, greatly simplifying the design and avoiding race conditions.

```ruby
# Core execution read loop inside Subshell#execute
accumulated_stdout = ""
accumulated_stderr = ""
stdout_done = false
stderr_done = false
exit_code = 0

out_sentinel = "#{token}_OUT"
err_sentinel = "#{token}_ERR"

loop do
  break if stdout_done && stderr_done

  # Multiplex streams with a standard timeout (default: 60s)
  ready = IO.select([@stdout, @stderr], nil, nil, timeout)
  raise Timeout::Error, "Command execution timed out after #{timeout} seconds" if ready.nil?

  ready[0].each do |stream|
    if stream == @stdout
      begin
        chunk = @stdout.read_nonblock(4096)
        accumulated_stdout << chunk
        
        # Check if we hit the boundary sentinel
        if accumulated_stdout.include?(out_sentinel)
          if match = accumulated_stdout.match(/#{out_sentinel}\s+(\d+)/)
            exit_code = match[1].to_i
            stdout_done = true
          end
        end

        # Yield raw chunks immediately to support real-time progress listeners
        yield :stdout, chunk if block_given?
      rescue IO::WaitReadable
        # No bytes available immediately, select will wait again
      rescue EOFError
        stdout_done = true
      end
    elsif stream == @stderr
      begin
        chunk = @stderr.read_nonblock(4096)
        accumulated_stderr << chunk

        if accumulated_stderr.include?(err_sentinel)
          stderr_done = true
        end

        yield :stderr, chunk if block_given?
      rescue IO::WaitReadable
      rescue EOFError
        stderr_done = true
      end
    end
  end
end
```

---

## 5. Hook Integrations

We will wire our persistent subshell directly into the `execute_command` tool workflow, invoking Norn's core hooks sequentially:

1. **`before_subprocess_execute` Hook**:
   ```ruby
   # inside plugins/subprocess_tools/plugin.rb tool block
   payload = { command: command }
   # Run through ROP middleware hook to allow inspection or parameter edits
   result = Norn::PluginManager.trigger_middleware(:before_subprocess_execute, payload)
   return result if result.failure?
   sanitized_command = result.value![:command]
   ```
2. **`on_subprocess_output` Hook**:
   * During the `IO.select` loop, every chunk read from stdout or stderr triggers:
     ```ruby
     Norn::PluginManager.trigger_notification(:on_subprocess_output, {
       stream: stream_type, # :stdout or :stderr
       chunk: chunk
     })
     ```
3. **`after_subprocess_execute` Hook**:
   * Once the command finishes executing, we trigger:
     ```ruby
     Norn::PluginManager.trigger_notification(:after_subprocess_execute, {
       command: sanitized_command,
       exit_code: outcome.exit_code,
       duration: duration
     })
     ```

---

## 6. Error Handling & Robust Edge Cases

* **Process Crashes / Sudden EOF**: If the background shell process dies (e.g. user ran `exit` or `kill -9`), reading from the streams will throw an `EOFError`. We rescue this, mark the subshell as `@started = false`, clean up remaining file descriptors, and return a clean failure outcome indicating the shell terminated.
* **Catastrophic Shell Actions**: Our existing `CommandValidator` remains our primary layer of safety, validating command strings *before* they are sent to the subshell stdin.
* **Sentinel Accidental Echoes**: In the extremely rare event that the user's command outputs strings matching our sentinel, we generate high-entropy randomized tokens (16 hexadecimal character UUIDs) to make accidental collisions statistically impossible.

---

## 7. Testing Strategy

We will write full-coverage unit and integration specs in `spec/norn/execution/subshell_spec.rb` and `spec/plugins/subprocess_tools/plugin_spec.rb` simulating persistent subshell routines:

1. **Directory Persistence Test**:
   ```ruby
   it "preserves directory shifts across distinct execute calls" do
     subshell = Norn::Execution::Subshell.new
     subshell.start
     
     subshell.execute("cd lib")
     outcome = subshell.execute("pwd")
     expect(outcome.stdout).to include("lib")
     
     subshell.stop
   end
   ```
2. **Environment Variable Persistence Test**:
   ```ruby
   it "retains exported environment variables" do
     subshell = Norn::Execution::Subshell.new
     subshell.start
     
     subshell.execute("export NORN_TEST_VAR=jester")
     outcome = subshell.execute("echo $NORN_TEST_VAR")
     expect(outcome.stdout.strip).to eq("jester")
     
     subshell.stop
   end
   ```
3. **Real-time Hook Emission Test**:
   Verify that emitting chunks dynamically triggers `:on_subprocess_output` subscriptions successfully.
