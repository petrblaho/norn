require "spec_helper"

RSpec.describe Norn::Plugins::Session::SessionPlugin, norn_plugins: :session do
  let(:plugin) { norn_plugin(:session) }
  let(:container) { Norn::Container }

  describe "Plugin configuration" do
    it "defines the correct plugin name" do
      expect(described_class.plugin_name).to eq("session")
    end

    it "subclasses Norn::Plugin" do
      expect(described_class.ancestors).to include(Norn::Plugin)
    end
  end

  describe "#on_boot" do
    it "registers the session in the container" do
      plugin.on_boot(container)
      
      # Resolve session and verify it is registered as an instance of Norn::Session
      session = container["session"]
      expect(session).to be_a(Norn::Session)
    end
  end

  describe "#on_tool_register" do
    let(:registry) { Norn::ToolRegistry }

    before do
      registry.clear!
    end

    after do
      registry.clear!
    end

    it "registers the get_session_stats tool in the registry" do
      plugin.on_tool_register(registry)
      tool = registry.resolve("get_session_stats")

      expect(tool).not_to be_nil
      expect(tool.name).to eq("get_session_stats")
      expect(tool.description).to include("Retrieve active session metrics")
    end
  end

  describe "Hooks" do
    let(:session) { Norn::Session.new }

    before do
      plugin.on_boot(container)
      # Override container registration with our local session double or instance for isolated testing
      allow(Norn).to receive(:[]).with("session").and_return(session)
    end

    describe "#before_llm_call" do
      it "records messages and overrides the history in session" do
        session.set(:history, [{ role: "user", content: "old message" }])

        messages = [
          { role: :system, content: "system instructions" },
          { role: :user, content: "new user prompt" }
        ]

        plugin.before_llm_call(messages)

        history = session.get(:history)
        expect(history.size).to eq(2)
        expect(history[0][:role]).to eq("system")
        expect(history[0][:content]).to eq("system instructions")
        expect(history[1][:role]).to eq("user")
        expect(history[1][:content]).to eq("new user prompt")
      end
    end

    describe "#after_llm_call" do
      it "appends the assistant reply to history" do
        session.set(:history, [])

        plugin.after_llm_call("this is a reply from the assistant")

        history = session.get(:history)
        expect(history.size).to eq(1)
        expect(history.first[:role]).to eq("assistant")
        expect(history.first[:content]).to eq("this is a reply from the assistant")
      end
    end

    describe "#on_render_response" do
      it "contributes session stats into ui_metadata without altering the text" do
        session.record_tokens(prompt: 10, completion: 5)
        payload = { text: "Hello", ui_metadata: {} }

        result = plugin.on_render_response(payload)
        expect(result[:text]).to eq("Hello")
        expect(result[:ui_metadata][:session_stats][:total_tokens]).to eq(15)
      end
    end
  end
end
