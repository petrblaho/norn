require "dry/monads"

module Norn
  module RSpec
    module LlmHelpers
      # Stubs the active LLM client with a single response.
      # If response is a String or Hash, it will automatically be wrapped in Dry::Monads::Success.
      def stub_llm_response(response, provider: nil)
        stub_llm_responses([response], provider: provider)
      end

      # Stubs the active LLM client with a sequence of responses.
      # If any response in the list is a String or Hash, it is wrapped in Dry::Monads::Success.
      def stub_llm_responses(responses, provider: nil)
        provider ||= Norn.config.llm_provider || "mock_provider"
        Norn.config.llm_provider = provider

        monadic_responses = Array(responses).map do |resp|
          if resp.is_a?(Dry::Monads::Result)
            resp
          else
            Dry::Monads::Success(resp)
          end
        end

        mock_client = double("LLMClient", model: "mock-model-#{provider}")

        # Ensure container is stubbed correctly
        allow(Norn::Container).to receive(:[]).and_call_original
        allow(Norn::Container).to receive(:[]).with("llm.#{provider}").and_return(mock_client)

        if monadic_responses.size == 1
          allow(mock_client).to receive(:call).and_return(monadic_responses.first)
        else
          allow(mock_client).to receive(:call).and_return(*monadic_responses)
        end

        mock_client
      end
    end
  end
end

RSpec.configure do |config|
  config.include Norn::RSpec::LlmHelpers
end
