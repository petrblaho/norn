require "spec_helper"
require_relative "../../../plugins/session_cli_formatter/plugin"
require_relative "../../../plugins/session/session"

RSpec.describe Norn::Plugins::SessionCliFormatter::SessionCliFormatterPlugin do
  let(:plugin) { described_class.new }
  let(:container) { Norn::Container }

  before do
    Norn::PluginManager.reset!
  end

  after do
    Norn::PluginManager.reset!
  end

  describe "Plugin configuration" do
    it "defines the correct plugin name" do
      expect(described_class.plugin_name).to eq("session_cli_formatter")
    end

    it "subclasses Norn::Plugin" do
      expect(described_class.ancestors).to include(Norn::Plugin)
    end
  end

  describe "#on_render_response" do
    context "when session stats metadata is not present in the payload" do
      it "returns the unmodified payload" do
        payload = { text: "Hello world", ui_metadata: {} }
        result = plugin.on_render_response(payload)
        expect(result[:text]).to eq("Hello world")
      end
    end

    context "when session stats metadata is present in the payload" do
      it "appends formatted token and tool usage metadata to the payload text" do
        payload = {
          text: "Response content",
          ui_metadata: {
            session_stats: {
              prompt_tokens: 15,
              completion_tokens: 5,
              total_tokens: 20,
              tool_calls: [{ tool: "file_read" }]
            }
          }
        }

        result = plugin.on_render_response(payload)

        expect(result[:text]).to include("Response content")
        # Matches "\e[90m(Tokens: 20 [P: 15 / C: 5] | Tools: 1)\e[0m"
        expect(result[:text]).to include("Tokens: 20")
        expect(result[:text]).to include("P: 15 / C: 5")
        expect(result[:text]).to include("Tools: 1")
      end
    end
  end
end
