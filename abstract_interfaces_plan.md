# Norn Abstract Base Classes & Boot-Time Interface Verification Plan

This document outlines the architectural plan to introduce strict structural enforcement in Norn. It defines abstract base classes for **Modes** and **Plugins** and establishes a boot-time reflection system to verify class interfaces before loading, ensuring absolute safety and stability.

---

## 1. The Core Architecture

In dynamically typed languages like Ruby, interfaces are normally verified only when a method is called. To prevent deep, nested runtime crashes during agent execution, Norn will introduce:
1. **Abstract Base Classes:** Base classes representing standard system blueprints, exposing mandatory abstract signatures using `NotImplementedError`.
2. **Boot-Time Reflection Verification:** Registration and loader hooks that inspect class capabilities (`instance_methods` and ancestry) upon loading, failing fast if any required interface contracts are violated.

---

## 2. Abstract Blueprints

### A. The `Norn::Mode` Base Class (`lib/norn/mode.rb`)
Every execution mode (e.g., `Chat`, `Task`) must inherit from `Norn::Mode` and implement its core contract.

```ruby
module Norn
  class Mode
    # The set of abstract instance methods that MUST be overridden
    ABSTRACT_METHODS = [:start, :interactive?, :allowed_capabilities, :instructions]

    def start(prompt = nil)
      raise NotImplementedError, "#{self.class} must implement #start"
    end

    def interactive?
      raise NotImplementedError, "#{self.class} must implement #interactive?"
    end

    def allowed_capabilities
      raise NotImplementedError, "#{self.class} must implement #allowed_capabilities"
    end

    def instructions
      raise NotImplementedError, "#{self.class} must implement #instructions"
    end
  end
end
```

### B. The `Norn::Plugin` Base Class (`lib/norn/plugin.rb`)
Every dynamic plugin must inherit from `Norn::Plugin` and expose standard hook methods.

```ruby
module Norn
  class Plugin
    # Abstract class method that MUST be overridden
    def self.plugin_name
      raise NotImplementedError, "Plugin class must define self.plugin_name"
    end

    # Optional lifecycle hooks - subclasses override if needed
    def on_boot(container); end
    def on_tool_register(registry); end
    def on_cli_register(cli); end
  end
end
```

---

## 3. Load-Time Reflection Verification

### A. Enforcing `Norn::Mode` Interface in `ModeRegistry`
When registering a mode, Norn inspects the class structure before completing registration:

```ruby
# In lib/norn/mode_registry.rb
def self.register(name, mode_class, description:)
  # 1. Enforce ancestry check (grand-grandchildren included)
  unless mode_class < Norn::Mode
    raise Norn::Error, "Registration Failure: Mode '#{name}' (#{mode_class}) must inherit from Norn::Mode"
  end

  # 2. Assert that all abstract methods are defined on the class or its ancestors (excluding Norn::Mode itself)
  missing_methods = Norn::Mode::ABSTRACT_METHODS.reject do |method|
    # Look up the inheritance chain, but stop before Norn::Mode to ensure the subclass implemented it
    mode_class.instance_methods.include?(method) && 
      mode_class.instance_method(method).owner != Norn::Mode
  end

  unless missing_methods.empty?
    raise Norn::Error, "Interface Violation: #{mode_class} must override abstract methods: #{missing_methods.join(', ')}"
  end

  # 3. Complete registration...
end
```

### B. Enforcing `Norn::Plugin` Interface in `PluginLoader`
When a dynamic plugin directory is loaded, Norn verifies that the class exposes the plugin contracts before loading:

```ruby
# In lib/norn/plugin_loader.rb
def self.load_plugin(plugin_class)
  # 1. Enforce Plugin Ancestry
  unless plugin_class < Norn::Plugin
    raise Norn::Error, "Plugin Load Failure: #{plugin_class} must inherit from Norn::Plugin"
  end

  # 2. Verify self.plugin_name is defined
  begin
    name = plugin_class.plugin_name
  rescue NotImplementedError
    raise Norn::Error, "Interface Violation: #{plugin_class} must define self.plugin_name"
  end

  # 3. Instantiate and safely load...
end
```

---

## 4. Critique & Structural Transition

1. **Object-Oriented Lifecycle:** This plan transitions Norn from a procedural callback model (`PluginManager.subscribe(:on_boot) { ... }`) to a clean, Object-Oriented plugin framework, greatly simplifying external developer contributions.
2. **Granular Verification:** By checking `owner != Norn::Mode`, Norn's verification catches subclasses that simply inherit the abstract methods without overriding them, closing a common loophole in abstract validations.
3. **Fail-Fast Boot:** Any typo or missing method triggers a detailed, readable boot-time error before any user execution begins.
