module Norn
  class Plugin
    @registered_plugins = []

    def self.inherited(subclass)
      super
      @registered_plugins << subclass
    end

    def self.registered_plugins
      @registered_plugins
    end

    def self.clear!
      @registered_plugins = []
    end

    # Abstract class method that MUST be overridden by subclasses
    def self.plugin_name
      raise NotImplementedError, "Plugin class must define self.plugin_name"
    end

    # Optional hook registration Phase 1: subclasses override this to declare custom events
    def self.declare_hooks(manager); end

    # Optional hook execution policies - subclasses override to specify recovery rules (e.g. { on_render_response: :recover })
    def self.hook_policies
      {}
    end

    # Optional lifecycle hooks - subclasses override if needed
    def on_boot(container); end
    def on_tool_register(registry); end
    def on_cli_register(cli); end
  end
end
