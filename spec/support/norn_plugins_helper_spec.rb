require "spec_helper"

RSpec.describe "Norn Plugin RSpec Helpers" do
  describe "norn_plugins metadata integration", norn_plugins: :tty_markdown do
    it "automatically registers and instantiates the specified plugin" do
      expect(Norn::PluginManager.active_plugins.size).to eq(1)
      expect(Norn::PluginManager.active_plugins.first).to be_a(TTYMarkdownPlugin)
    end

    it "allows accessing the plugin instance using norn_plugin helper" do
      expect(norn_plugin(:tty_markdown)).to be_a(TTYMarkdownPlugin)
    end

    it "raises a clear error if trying to access an inactive plugin" do
      expect {
        norn_plugin(:non_existent_plugin)
      }.to raise_error(/Norn Plugin :non_existent_plugin is not active in this test/)
    end

    it "provides a hash of active plugins through norn_plugins" do
      expect(norn_plugins).to have_key(:tty_markdown)
      expect(norn_plugins[:tty_markdown]).to be_a(TTYMarkdownPlugin)
    end
  end

  describe "norn_plugins with multiple plugins", norn_plugins: [:tty_markdown, :prompt_user] do
    it "registers and instantiates all specified plugins" do
      expect(norn_plugins.keys).to contain_exactly(:tty_markdown, :prompt_user)
      expect(norn_plugin(:tty_markdown)).to be_a(TTYMarkdownPlugin)
      expect(norn_plugin(:prompt_user)).to be_a(PromptUserPlugin)
    end
  end
end
