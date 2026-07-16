require "json"

module Norn
  module Plugins
    module A2A
      class NullStream
        def print(*args); end
        def puts(*args); end
        def write(*args); end
      end

      class A2AContext
        attr_reader :output
        def initialize
          @output = NullStream.new
        end
      end

      class Server
        def initialize(transport:, registry: Norn::ToolRegistry)
          @transport = transport
          @registry = registry
          @active_execution_id = nil
          @streaming = nil
          @last_exit_code = 0
          @last_duration = nil
          
          # Dynamically bind to Norn's real-time subprocess streaming hooks
          setup_hooks!
        end

        def handle_message(raw_json)
          begin
            request = JSON.parse(raw_json, symbolize_names: true)
            method = request[:method].to_s
            id = request[:id]

            case method
            when "agent.getExtendedAgentCard"
              handle_discovery(id)
            when "agent.sendMessage"
              handle_execute(request, id, streaming: false)
            when "agent.sendStreamingMessage"
              handle_execute(request, id, streaming: true)
            else
              write_error(id, -32601, "Method not found: #{method}")
            end
          rescue => e
            write_error(nil, -32700, "Parse error: #{e.message}")
          end
        end

        private

        def setup_hooks!
          Norn::PluginManager.subscribe(:on_subprocess_output) do |payload|
            if @active_execution_id && @streaming
              # Format to official A2A agent.onProgress notification frame
              notification = {
                jsonrpc: "2.0",
                method: "agent.onProgress",
                params: {
                  stream: payload[:stream].to_s,
                  chunk: payload[:chunk]
                }
              }
              @transport.write(JSON.generate(notification))
            end
          end

          Norn::PluginManager.subscribe(:after_subprocess_execute) do |payload|
            if @active_execution_id
              @last_exit_code = payload[:exit_code]
              @last_duration = payload[:duration]
            end
          end
        end

        def handle_discovery(id)
          skills = @registry.registered_tools.map do |tool|
            {
              name: tool.name,
              description: tool.description,
              schema: tool.parameters
            }
          end

          # Schema-compliant A2A AgentCard
          result = {
            name: "norn",
            version: "1.0.0",
            capabilities: {
              streaming: true,
              push_notifications: false,
              extended_agent_card: true
            },
            skills: skills
          }

          write_success(id, result)
        end

        def handle_execute(request, id, streaming:)
          parts = request.dig(:params, :message, :parts) || []
          prompt_text = parts.first ? parts.first[:text].to_s.strip : ""

          # A2A simple parsing: extract command/tool. Format: "tool_name arg1='val' arg2=val"
          # Match tool_name and split remaining properties
          tool_name = prompt_text.split(/\s+/).first || ""
          args_part = tool_name.empty? ? "" : prompt_text[tool_name.length..-1].to_s.strip

          tool = @registry.resolve(tool_name)
          unless tool
            return write_error(id, -32602, "Tool not found: #{tool_name}")
          end

          # Parse arguments (matches key='val' or key=val)
          arguments = {}
          args_part.scan(/(\w+)=['"]?([^'"]+)['"]?/).each do |key, val|
            arguments[key.to_sym] = val
          end

          # Set active execution context for progress hooks routing
          @active_execution_id = id
          @streaming = streaming
          @last_exit_code = 0
          @last_duration = nil

          session = Norn["session"] rescue nil
          start_tokens = session ? session.to_h : nil
          start_time = Time.now

          begin
            outcome_text = tool.call(arguments, A2AContext.new)

            end_time = Time.now
            duration = @last_duration || (end_time - start_time)
            exit_code = @last_exit_code

            # Calculate token delta
            token_delta = { prompt: 0, completion: 0, total: 0 }
            if session && start_tokens
              end_tokens = session.to_h
              token_delta[:prompt] = end_tokens[:prompt_tokens] - start_tokens[:prompt_tokens]
              token_delta[:completion] = end_tokens[:completion_tokens] - start_tokens[:completion_tokens]
              token_delta[:total] = end_tokens[:total_tokens] - start_tokens[:total_tokens]
            end

            # Send task completed notification
            completed_notification = {
              jsonrpc: "2.0",
              method: "agent.onTaskCompleted",
              params: {
                task_id: "task_#{id}",
                metrics: {
                  duration: duration.to_f,
                  exit_code: exit_code.to_i,
                  tokens: {
                    prompt: token_delta[:prompt],
                    completion: token_delta[:completion],
                    total: token_delta[:total]
                  }
                }
              }
            }
            @transport.write(JSON.generate(completed_notification))

            # Compliant A2A Task result payload
            result = {
              id: "task_#{id}",
              status: {
                state: "COMPLETED"
              },
              parts: [
                { text: outcome_text }
              ]
            }
            write_success(id, result)
          rescue => e
            write_error(id, -32603, "Internal error during tool call: #{e.message}")
          ensure
            @active_execution_id = nil
            @streaming = nil
          end
        end

        def write_success(id, result)
          response = {
            jsonrpc: "2.0",
            result: result,
            id: id
          }
          @transport.write(JSON.generate(response))
        end

        def write_error(id, code, message)
          response = {
            jsonrpc: "2.0",
            error: {
              code: code,
              message: message
            },
            id: id
          }
          @transport.write(JSON.generate(response))
        end
      end
    end
  end
end
