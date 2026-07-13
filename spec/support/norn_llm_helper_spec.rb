require "spec_helper"

RSpec.describe "Norn LLM RSpec Helpers" do
  describe "#stub_llm_response" do
    it "registers the provider and returns Success wrapped string" do
      # Using current default provider ("openai")
      client = stub_llm_response("Hello mock!")
      
      expect(Norn.config.llm_provider).to eq("openai")
      expect(Norn::Container["llm.openai"]).to eq(client)
      
      response = client.call([])
      expect(response).to be_success
      expect(response.value!).to eq("Hello mock!")
    end

    it "handles hashes successfully" do
      client = stub_llm_response({ type: :tool_call, calls: [] })
      response = client.call([])
      
      expect(response).to be_success
      expect(response.value![:type]).to eq(:tool_call)
    end

    it "supports explicitly setting a provider" do
      client = stub_llm_response("Hello custom!", provider: "my_custom_provider")
      
      expect(Norn.config.llm_provider).to eq("my_custom_provider")
      expect(Norn::Container["llm.my_custom_provider"]).to eq(client)
    end
  end

  describe "#stub_llm_responses" do
    it "handles a sequence of responses and cycles through them" do
      client = stub_llm_responses(["First", "Second"])
      
      res1 = client.call([])
      res2 = client.call([])
      
      expect(res1.value!).to eq("First")
      expect(res2.value!).to eq("Second")
    end
  end
end
