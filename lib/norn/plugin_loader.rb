module Norn
  class PluginLoader
    class << self
      # Scans the top-level plugins/ directory for subdirectories and requires their plugin.rb entrypoint.
      def load_all
        plugins_dir = File.expand_path("../../plugins", __dir__)
        return unless Dir.exist?(plugins_dir)

        # Iterate over all entries in the plugins folder
        Dir.glob(File.join(plugins_dir, "*")).each do |path|
          next unless File.directory?(path)

          plugin_entry = File.join(path, "plugin.rb")
          if File.exist?(plugin_entry)
            require plugin_entry
          end
        end
      end
    end
  end
end
