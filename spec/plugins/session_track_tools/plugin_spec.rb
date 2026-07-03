require "spec_helper"
require_relative "../../../plugins/session/session"
require_relative "../../../plugins/session_track_tools/plugin"

RSpec.describe Norn::Plugins::SessionTrackTools::SessionTrackToolsPlugin do
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
      expect(described_class.plugin_name).to eq("session_track_tools")
    end

    it "subclasses Norn::Plugin" do
      expect(described_class.ancestors).to include(Norn::Plugin)
    end
  end

  describe "#after_tool_call" do
    it "records the tool call details in the session" do
      expect(session.get(:tool_calls)).to be_empty

      plugin.after_tool_call("file_read", { path: "foo.txt" }, "success content", nil)

      tool_calls = session.get(:tool_calls)
      expect(tool_calls.size).to eq(1)
      expect(tool_calls.first[:tool]).to eq("file_read")
      expect(tool_calls.first[:arguments]).to eq({ path: "foo.txt" })
      expect(tool_calls.first[:result]).to eq("success content")
      expect(tool_calls.first[:error]).to be_nil
    end

    it "records error details when a tool call fails" do
      plugin.after_tool_call("file_write", { path: "protected.txt" }, nil, "Permission Denied")

      tool_calls = session.get(:tool_calls)
      expect(tool_calls.size).to eq(1)
      expect(tool_calls.first[:tool]).to eq("file_write")
      expect(tool_calls.first[:arguments]).to eq({ path: "protected.txt" })
      expect(tool_calls.first[:result]).to be_nil
      expect(tool_calls.first[:error]).to eq("Permission Denied")
    end
  end
end
