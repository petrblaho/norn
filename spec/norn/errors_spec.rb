require "spec_helper"
require "norn/errors"

RSpec.describe Norn::FailurePayload do
  describe "#message" do
    it "keeps normal safe messages completely unchanged" do
      payload = described_class.new("This is a safe message with no keys.")
      expect(payload.message).to eq("This is a safe message with no keys.")
    end

    it "redacts Gemini URL query parameter key=VALUE" do
      raw_error = "status 400 for POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:streamGenerateContent?key=AIzaSyD-xyz123_abc.def.ghi"
      payload = described_class.new(raw_error)
      
      expect(payload.message).to eq("status 400 for POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:streamGenerateContent?key=[REDACTED]")
    end

    it "redacts Gemini URL parameter key=VALUE when inside ampersand queries" do
      raw_error = "https://generativelanguage.googleapis.com/v1beta/models?param=1&key=AIzaSyD-xyz123&other=2"
      payload = described_class.new(raw_error)
      
      expect(payload.message).to eq("https://generativelanguage.googleapis.com/v1beta/models?param=1&key=[REDACTED]&other=2")
    end

    it "redacts OpenAI api keys starting with sk-..." do
      raw_error = "OpenAI request failed: unauthorized. Used key: sk-51a8f9c10d3e2b4f6a7c8e9d0c1b2a3f4e5d6c7b"
      payload = described_class.new(raw_error)
      
      expect(payload.message).to eq("OpenAI request failed: unauthorized. Used key: sk-...[REDACTED]")
    end

    it "redacts HTTP Authorization Bearer tokens" do
      raw_error = "Header sent: Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ"
      payload = described_class.new(raw_error)
      
      expect(payload.message).to eq("Header sent: Authorization: Bearer [REDACTED]")
    end
  end

  describe "#context" do
    it "dynamically remembers identified keys and scrubs them even from other formats (like Hash params)" do
      raw_error = "Error from POST https://api.com?key=AIzaSyD-secret_key_123"
      payload = described_class.new(raw_error, { query_params: { "key" => "AIzaSyD-secret_key_123" } })
      
      expect(payload.message).to eq("Error from POST https://api.com?key=[REDACTED]")
      expect(payload.context[:query_params]["key"]).to eq("[REDACTED]")
    end

    it "deeply sanitizes nested strings and raw Exception objects in the context" do
      class CustomTestError < StandardError; end
      raw_exception = CustomTestError.new("Failed connection with key=SECRET_KEY")

      context = {
        nested_hash: {
          api_key: "sk-abcdef1234567890abcdef1234567890"
        },
        api_url: "https://domain.com?key=SECRET_KEY",
        original_error: raw_exception,
        safe_param: 123
      }

      payload = described_class.new("Error", context)
      
      expect(payload.context[:nested_hash][:api_key]).to eq("sk-...[REDACTED]")
      expect(payload.context[:api_url]).to eq("https://domain.com?key=[REDACTED]")
      expect(payload.context[:original_error]).to include("key=[REDACTED]")
      expect(payload.context[:safe_param]).to eq(123)
    end
  end
end
