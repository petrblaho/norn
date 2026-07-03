require "spec_helper"
require_relative "../../../plugins/session/session"
require_relative "../../../plugins/session_track_tokens/plugin"

RSpec.describe Norn::Plugins::SessionTrackTokens::SessionTrackTokensPlugin do
  let(:plugin) { described_class.new }
  let(:session) { Norn::Session.new }

  before do
    Norn::PluginManager.reset!
    Norn::PluginManager.register_core_hooks!
    allow(Norn).to receive(:[]).with("session").and_return(session)
  end

  after do
    Norn::PluginManager.reset!
  end

  describe "Plugin configuration" do
    it "defines the correct plugin name" do
      expect(described_class.plugin_name).to eq("session_track_tokens")
    end

    it "subclasses Norn::Plugin" do
      expect(described_class.ancestors).to include(Norn::Plugin)
    end
  end

  describe "#after_llm_response" do
    it "does nothing if the response does not contain usage metadata" do
      response = { type: :text, content: "Hello" }
      plugin.after_llm_response(response, "openai", "gpt-4o-mini")

      expect(session.get(:prompt_tokens)).to eq(0)
      expect(session.get(:completion_tokens)).to eq(0)
    end

    it "records the token count in the session when usage is present" do
      response = {
        type: :text,
        content: "Hello",
        usage: { prompt_tokens: 12, completion_tokens: 8 }
      }
      plugin.after_llm_response(response, "openai", "gpt-4o-mini")

      expect(session.get(:prompt_tokens)).to eq(12)
      expect(session.get(:completion_tokens)).to eq(8)
      expect(session.get(:total_tokens)).to eq(20)

      provider_usage = session.get(:provider_usage)
      expect(provider_usage[:openai][:"gpt-4o-mini"]).to eq({
        prompt_tokens: 12,
        completion_tokens: 8,
        total_tokens: 20
      })
    end
  end
end
