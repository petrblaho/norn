require "spec_helper"
require "norn/mode"
require "norn/mode_registry"
require "norn/plugin"
require "norn/tool"
require "norn/tool_registry"

RSpec.describe "Centralized Codebase Static-Analysis & Contract Enforcement" do
  describe "Norn::Mode Class-Hierarchy Contracts" do
    it "ensures all registered modes inherit from Norn::Mode" do
      Norn::ModeRegistry.registered_modes.each do |mode_name|
        mode_class = Norn::ModeRegistry.resolve(mode_name)
        expect(mode_class).to be < Norn::Mode
      end
    end

    it "ensures all registered modes implement the mandatory public abstract interface methods" do
      Norn::ModeRegistry.registered_modes.each do |mode_name|
        mode_class = Norn::ModeRegistry.resolve(mode_name)
        
        # Verify mandatory abstract overrides are defined
        Norn::Mode::ABSTRACT_METHODS.each do |method|
          expect(mode_class.instance_methods).to include(method)
          # Exclude base class definition to ensure subclass implemented it
          expect(mode_class.instance_method(method).owner).not_to eq(Norn::Mode)
        end
      end
    end
  end

  describe "Norn::Tool Block Arity & Parameter Contracts" do
    it "ensures all registered tools in the registry have valid block arity signatures (args or args+context)" do
      # Load all standard tools
      Norn::ToolRegistry.registered_tools.each do |tool|
        expect(tool.block).not_to be_nil
        # Block arity must be either 1 (args), 2 (args, context), or -1 (variable arguments)
        expect([-1, 1, 2]).to include(tool.block.arity)
      end
    end
  end

  describe "Norn::Plugin Lifecycle Contracts" do
    it "ensures all active class-based plugins inherit from Norn::Plugin" do
      Norn::Plugin.registered_plugins.each do |plugin_class|
        expect(plugin_class).to be < Norn::Plugin
      end
    end

    it "ensures all active class-based plugins override the mandatory self.plugin_name class method" do
      Norn::Plugin.registered_plugins.each do |plugin_class|
        expect { plugin_class.plugin_name }.not_to raise_error
        expect(plugin_class.plugin_name).to be_a(String)
      end
    end
  end
end
