require "gemini-ai"
require "json"
require "dry/monads"

module Norn
  module Plugins
    module Gemini
      class Client
        include Dry::Monads[:result]

        DEFAULT_MODEL = "gemini-3.5-flash"

        def initialize(api_key: ENV["GEMINI_API_KEY"])
          @api_key = api_key
        end

        def call(messages, tools: nil)
          if @api_key.nil? || @api_key.empty?
            return Failure(Norn::FailurePayload.new(
              Norn::ProviderError.new("GEMINI_API_KEY environment variable is not set."),
              { provider: :gemini, model: DEFAULT_MODEL }
            ))
          end

          begin
            gemini_client = ::Gemini.new(
              credentials: {
                service: "generative-language-api",
                api_key: @api_key,
                version: "v1beta"
              },
              options: {
                model: DEFAULT_MODEL
              }
            )

            # Separate system messages from conversation history for Gemini's API
            system_msgs, other_msgs = messages.partition { |msg| msg[:role] == :system || msg[:role] == "system" }

            # Translate non-system messages to Gemini format
            formatted_messages = other_msgs.map do |msg|
              role = msg[:role] == :assistant || msg[:role] == "assistant" ? "model" : (msg[:role] == :tool || msg[:role] == "tool" ? "function" : "user")
              
              parts = if msg[:parts]
                        msg[:parts]
                      elsif msg[:role].to_s == "assistant" && msg[:tool_calls]
                        msg[:tool_calls].map do |tc|
                          {
                            functionCall: {
                              name: tc[:name],
                              args: tc[:arguments]
                            }
                          }
                        end
                      elsif msg[:role].to_s == "tool"
                        [
                          {
                            functionResponse: {
                              name: msg[:name],
                              response: { output: msg[:content] }
                            }
                          }
                        ]
                      elsif msg[:content].is_a?(String)
                        [{ text: msg[:content] }]
                      else
                        [{ text: msg[:content].to_s }]
                      end
              
              {
                role: role,
                parts: parts
              }
            end

            request_params = { contents: formatted_messages }

            if system_msgs.any?
              system_content = system_msgs.map { |msg| msg[:content] }.join("\n\n")
              request_params[:system_instruction] = {
                role: "user",
                parts: [{ text: system_content }]
              }
            end

            # If tools are present, construct functionDeclarations in the tools payload
            if tools && !tools.empty?
              function_declarations = tools.map do |tool|
                params_schema = deep_uppercase_types(tool.parameters)
                {
                  name: tool.name,
                  description: tool.description,
                  parameters: params_schema
                }
              end
              request_params[:tools] = [{ function_declarations: function_declarations }]
            end

            # Call stream_generate_content with server_sent_events disabled to get the complete response
            result = gemini_client.stream_generate_content(
              request_params,
              server_sent_events: false
            )

            # Parse the response for functionCalls or text
            function_calls = []
            if result.is_a?(Array)
              result.each do |res|
                candidates = res["candidates"] || res[:candidates]
                next unless candidates.is_a?(Array)

                candidates.each do |candidate|
                  parts = candidate.dig("content", "parts") || candidate.dig(:content, :parts)
                  next unless parts.is_a?(Array)

                  parts.each do |part|
                    fc = part["functionCall"] || part[:functionCall]
                    if fc
                      name = fc["name"] || fc[:name]
                      args = fc["args"] || fc[:args]
                      function_calls << { id: nil, name: name, arguments: args }
                    end
                  end
                end
              end
            elsif result.is_a?(Hash)
              candidates = result["candidates"] || result[:candidates]
              if candidates.is_a?(Array)
                candidates.each do |candidate|
                  parts = candidate.dig("content", "parts") || candidate.dig(:content, :parts)
                  next unless parts.is_a?(Array)

                  parts.each do |part|
                    fc = part["functionCall"] || part[:functionCall]
                    if fc
                      name = fc["name"] || fc[:name]
                      args = fc["args"] || fc[:args]
                      function_calls << { id: nil, name: name, arguments: args }
                    end
                  end
                end
              end
            end

            # Extract raw candidates' parts to preserve thought signatures
            raw_parts = nil
            if result.is_a?(Array)
              raw_parts = result.flat_map do |res|
                candidates = res["candidates"] || res[:candidates]
                next [] unless candidates.is_a?(Array)
                candidates.flat_map do |candidate|
                  candidate.dig("content", "parts") || candidate.dig(:content, :parts) || []
                end
              end.compact
            elsif result.is_a?(Hash)
              candidates = result["candidates"] || result[:candidates]
              if candidates.is_a?(Array) && candidates.any?
                raw_parts = candidates[0].dig("content", "parts") || candidates[0].dig(:content, :parts)
              end
            end

            parsed_response = if function_calls.any?
              { type: :tool_call, calls: function_calls, parts: raw_parts }
            else
              text = if result.is_a?(Array)
                       result.map { |res| res.dig("candidates", 0, "content", "parts", 0, "text") }.compact.join
                     elsif result.is_a?(Hash)
                       result.dig("candidates", 0, "content", "parts", 0, "text") || ""
                     else
                       ""
                     end
              { type: :text, content: text, parts: raw_parts }
            end

            Success(parsed_response)
          rescue => e
            Failure(Norn::FailurePayload.new(
              Norn::ProviderError.new("Gemini API error: #{e.message}"),
              { provider: :gemini, model: DEFAULT_MODEL, original_error: e }
            ))
          end
        end

        private

        def deep_uppercase_types(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), hash|
              if k.to_s == "type" && v.is_a?(String)
                hash[k] = v.upcase
              else
                hash[k] = deep_uppercase_types(v)
              end
            end
          when Array
            value.map { |item| deep_uppercase_types(item) }
          else
            value
          end
        end
      end
    end
  end
end
