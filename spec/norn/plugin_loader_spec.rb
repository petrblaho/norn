require "spec_helper"

RSpec.describe Norn::PluginLoader do
  describe ".load_all" do
    it "finds plugin directories and requires their plugin.rb files" do
      # Mock the directory structure
      plugins_dir = File.expand_path("../../plugins", __dir__)
      allow(Dir).to receive(:exist?).with(plugins_dir).and_return(true)
      allow(Dir).to receive(:glob).with(File.join(plugins_dir, "*")).and_return([
        File.join(plugins_dir, "test_plugin")
      ])
      allow(File).to receive(:directory?).with(File.join(plugins_dir, "test_plugin")).and_return(true)
      allow(File).to receive(:exist?).with(File.join(plugins_dir, "test_plugin", "plugin.rb")).and_return(true)

      # Expect the load loader to require the plugin file
      expect(Norn::PluginLoader).to receive(:require).with(File.join(plugins_dir, "test_plugin", "plugin.rb"))

      described_class.load_all
    end
  end
end
