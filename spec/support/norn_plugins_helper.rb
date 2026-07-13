module Norn
  module RSpec
    module PluginHelpers
      # Resolves an active plugin instance by its plugin_name (string or symbol)
      def norn_plugin(name)
        target_name = name.to_s
        instance = Norn::PluginManager.active_plugins.find do |plugin|
          plugin.class.respond_to?(:plugin_name) && plugin.class.plugin_name.to_s == target_name
        end

        unless instance
          raise "Norn Plugin #{name.inspect} is not active in this test. " \
                "Ensure you've declared it via `norn_plugins: #{name.inspect}`."
        end

        instance
      end

      # Returns a Hash of active plugin name symbols mapped to their active instances
      def norn_plugins
        Norn::PluginManager.active_plugins.each_with_object({}) do |plugin, hash|
          if plugin.class.respond_to?(:plugin_name)
            hash[plugin.class.plugin_name.to_sym] = plugin
          end
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include Norn::RSpec::PluginHelpers

  config.before(:each) do |example|
    if example.metadata[:norn_plugins]
      # 1. Clean PluginManager state completely
      Norn::PluginManager.reset!
      Norn::PluginManager.register_core_hooks!

      # 2. Extract requested plugins
      requested = Array(example.metadata[:norn_plugins]).map(&:to_s)

      # 3. Find registered plugins by plugin_name
      matching_classes = Norn::Plugin.registered_plugins.select do |klass|
        klass.respond_to?(:plugin_name) && requested.include?(klass.plugin_name.to_s)
      end

      # 4. Handle any missing/not found plugins gracefully with a clear error
      found_names = matching_classes.map { |k| k.plugin_name.to_s }
      missing = requested - found_names
      if missing.any?
        raise "Requested Norn plugins not found/loaded: #{missing.join(', ')}. " \
              "Available plugins: #{Norn::Plugin.registered_plugins.map { |k| k.respond_to?(:plugin_name) ? k.plugin_name : k.name }.join(', ')}"
      end

      # 5. Instantiate and assign active plugins
      active_instances = matching_classes.map(&:new)
      Norn::PluginManager.active_plugins = active_instances

      # 6. Declare hooks and on_boot for these plugins
      matching_classes.each do |klass|
        klass.declare_hooks(Norn::PluginManager)
      end

      active_instances.each do |instance|
        instance.on_boot(Norn::Container) if instance.respond_to?(:on_boot)
      end
    end
  end
end
