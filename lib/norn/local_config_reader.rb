require "yaml"
require "json"

module Norn
  class LocalConfigReader
    attr_reader :root_path

    def initialize(root_path = nil)
      @root_path = root_path || begin
        Norn::Container.config.root
      rescue => e
        Dir.pwd
      end
    end

    def local_config_paths
      [
        File.join(@root_path, ".norn.yml"),
        File.join(@root_path, ".norn.yaml"),
        File.join(@root_path, ".norn.json")
      ]
    end

    def read
      local_config_paths.each do |path|
        next unless File.exist?(path)

        begin
          if path.end_with?(".json")
            return parse_json(path)
          else
            return parse_yaml(path)
          end
        rescue => e
          warn "Norn Config Error: Failed to parse #{path} - #{e.message}"
        end
      end
      {}
    end

    private

    def parse_json(path)
      data = JSON.parse(File.read(path))
      symbolize_keys(data)
    end

    def parse_yaml(path)
      data = YAML.load_file(path)
      symbolize_keys(data)
    end

    def symbolize_keys(hash)
      return {} unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
      end
    end
  end
end
