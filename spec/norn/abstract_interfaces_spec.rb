require "spec_helper"
require "norn/mode"
require "norn/mode_registry"
require "norn/plugin"

RSpec.describe "Boot-Time Interface and Subclass Verification" do
  before do
    Norn::ModeRegistry.clear!
  end

  after do
    # Restore standard modes to registry
    Norn::ModeRegistry.clear!
    Norn::ModeRegistry.register("chat", Norn::Modes::Chat, description: "Chat")
    Norn::ModeRegistry.register("task", Norn::Modes::Task, description: "Task")
    Norn::ModeRegistry.register("dev", Norn::Modes::Dev, description: "Dev")
  end

  describe "Norn::Mode Registry contract verification" do
    it "allows registering a class that inherits from Norn::Mode and overrides all abstract methods" do
      valid_mode_class = Class.new(Norn::Mode) do
        def start(prompt = nil); end
        def interactive?; true; end
        def allowed_capabilities; []; end
        def instructions; "valid"; end
        def banner_name; "valid"; end
      end

      expect {
        Norn::ModeRegistry.register("valid_mode", valid_mode_class, description: "A valid mode")
      }.not_to raise_error

      expect(Norn::ModeRegistry.registered_modes).to include("valid_mode")
    end

    it "raises a Norn::Error if the registered class does not inherit from Norn::Mode" do
      invalid_class = Class.new do
        def start(prompt = nil); end
      end

      expect {
        Norn::ModeRegistry.register("invalid_mode", invalid_class, description: "Invalid subclass")
      }.to raise_error(Norn::Error, /must inherit from Norn::Mode/)
    end

    it "raises a Norn::Error if any required abstract methods are not overridden" do
      # Forgets to override allowed_capabilities and interactive?
      incomplete_mode_class = Class.new(Norn::Mode) do
        def start(prompt = nil); end
        def instructions; "incomplete"; end
      end

      expect {
        Norn::ModeRegistry.register("incomplete", incomplete_mode_class, description: "Incomplete")
      }.to raise_error(Norn::Error, /must implement abstract methods.*interactive.*allowed_capabilities/)
    end
  end

  describe "Norn::Plugin contract verification" do
    it "automatically registers subclass definitions into Norn::Plugin.registered_plugins" do
      plugin_class = Class.new(Norn::Plugin) do
        def self.plugin_name; "test_plugin"; end
      end

      expect(Norn::Plugin.registered_plugins).to include(plugin_class)
    end
  end
end
