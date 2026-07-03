require "openai"
require "json"
require "dry/monads"

module Norn
  module Plugins
    module OpenAI
      class Client
        include Dry::Monads[:result]

        DEFAULT_MODEL = "gpt-4o-mini"

        attr_reader :model, :temperature

        def initialize(api_key: ENV["OPENAI_API_KEY"], model: nil, temperature: nil)
          @api_key = api_key
          @model = model || Norn.config.openai_model || DEFAULT_MODEL
          @temperature = temperature || Norn.config.temperature || 0.7
        end

        def call(messages, tools: nil)
          if @api_key.nil? || @api_key.empty?
            return Failure(Norn::FailurePayload.new(
              Norn::ProviderError.new("OPENAI_API_KEY environment variable is not set."),
              { provider: :openai, model: @model }
            ))
          end

          begin
            openai_client = ::OpenAI::Client.new(api_key: @api_key)
            
            # Translate unified message format (ensuring roles & keys match what OpenAI expects)
            formatted_messages = messages.map do |msg|
              m = {
                role: msg[:role].to_sym,
                content: msg[:content]
              }
              if msg[:role].to_s == "assistant" && msg[:tool_calls]
                m[:tool_calls] = msg[:tool_calls].map do |tc|
                  {
                    id: tc[:id],
                    type: "function",
                    function: {
                      name: tc[:name],
                      arguments: tc[:arguments].is_a?(String) ? tc[:arguments] : tc[:arguments].to_json
                    }
                  }
                end
              elsif msg[:role].to_s == "tool"
                m[:tool_call_id] = msg[:tool_call_id]
              end
              m
            end

            params = {
              model: @model,
              temperature: @temperature,
              input: formatted_messages
            }

            if tools && !tools.empty?
              params[:tools] = tools.map do |tool|
                {
                  type: "function",
                  function: {
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.parameters
                  }
                }
              end
            end

            response = openai_client.responses.create(**params)

            # Parse the response for tool_calls or function_calls
            tool_calls = []
            if response.respond_to?(:output) && response.output.is_a?(Array)
              response.output.each do |item|
                if item.respond_to?(:type) && item.type == :function_call
                  id = item.respond_to?(:call_id) ? item.call_id : (item.respond_to?(:id) ? item.id : nil)
                  name = item.name
                  arguments = item.arguments
                  tool_calls << { id: id, name: name, arguments: arguments }
                end
              end
            elsif response.is_a?(Hash)
              raw_calls = response["tool_calls"] || response[:tool_calls] || response.dig("choices", 0, "message", "tool_calls") || response.dig(:choices, 0, :message, :tool_calls)
              if raw_calls&.is_a?(Array)
                raw_calls.each do |rc|
                  id = rc["id"] || rc[:id]
                  func = rc["function"] || rc[:function]
                  if func
                    name = func["name"] || func[:name]
                    arguments = func["arguments"] || func[:arguments]
                    tool_calls << { id: id, name: name, arguments: arguments }
                  end
                end
              end
            end

            # Support function_calls fallback if any
            function_calls = []
            if response.respond_to?(:function_calls) && response.function_calls
              response.function_calls.each do |fc|
                id = fc.respond_to?(:id) ? fc.id : (fc["id"] || fc[:id])
                name = fc.respond_to?(:name) ? fc.name : (fc["name"] || fc[:name])
                arguments = fc.respond_to?(:arguments) ? fc.arguments : (fc["arguments"] || fc[:arguments])
                function_calls << { id: id, name: name, arguments: arguments }
              end
            elsif response.is_a?(Hash)
              raw_fcs = response["function_calls"] || response[:function_calls] || response.dig("choices", 0, "message", "function_call")
              if raw_fcs
                # Normalize single function_call into an array
                raw_fcs = [raw_fcs] unless raw_fcs.is_a?(Array)
                raw_fcs.each do |fc|
                  id = fc["id"] || fc[:id]
                  name = fc["name"] || fc[:name]
                  arguments = fc["arguments"] || fc[:arguments]
                  function_calls << { id: id, name: name, arguments: arguments }
                end
              end
            end

            active_calls = tool_calls.any? ? tool_calls : function_calls

            parsed_response = if active_calls.any?
              parsed_calls = active_calls.map do |tc|
                args_raw = tc[:arguments]
                args = if args_raw.is_a?(String)
                         begin
                           JSON.parse(args_raw)
                         rescue
                           args_raw
                         end
                       else
                         args_raw
                       end
                {
                  id: tc[:id],
                  name: tc[:name],
                  arguments: args
                }
              end
              { type: :tool_call, calls: parsed_calls }
            else
              { type: :text, content: response.output_text }
            end

            # Extract usage from OpenAI response if available
            usage = nil
            if response.respond_to?(:usage) && response.usage
              usage_obj = response.usage
              if usage_obj.is_a?(Hash)
                usage = {
                  prompt_tokens: usage_obj["prompt_tokens"] || usage_obj[:prompt_tokens] || 0,
                  completion_tokens: usage_obj["completion_tokens"] || usage_obj[:completion_tokens] || 0
                }
              elsif usage_obj.respond_to?(:prompt_tokens)
                usage = {
                  prompt_tokens: usage_obj.prompt_tokens || 0,
                  completion_tokens: usage_obj.completion_tokens || 0
                }
              end
            elsif response.is_a?(Hash) && (response["usage"] || response[:usage])
              u = response["usage"] || response[:usage]
              usage = {
                prompt_tokens: u["prompt_tokens"] || u[:prompt_tokens] || 0,
                completion_tokens: u["completion_tokens"] || u[:completion_tokens] || 0
              }
            end

            parsed_response[:usage] = usage if usage && parsed_response.is_a?(Hash)

            Success(parsed_response)
          rescue => e
            Failure(Norn::FailurePayload.new(
              Norn::ProviderError.new("OpenAI API error: #{e.message}"),
              { provider: :openai, model: @model, original_error: e }
            ))
          end
        end
      end
    end
  end
end
