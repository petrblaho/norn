require "yaml"
require "json"
require "dry/schema"

module Norn
  class ConfigLoader
    # Define validation schema for our configuration using dry-schema
    Schema = Dry::Schema.Params do
      optional(:llm_provider).filled(:string, included_in?: ["openai", "gemini"])
      optional(:sandbox_info).maybe(:string)
      optional(:openai_model).maybe(:string)
      optional(:gemini_model).maybe(:string)
      optional(:temperature).maybe(:float)
      optional(:git_addon_enabled).maybe(:bool)
      optional(:git_addon_message).maybe(:string)
      optional(:session_cli_format).maybe(:string)
      optional(:workspace_root).maybe(:string)
      
      # New instruction structure
      optional(:instructions).hash do
        optional(:clear).array(:string)
        optional(:base).maybe(:string)
        optional(:prepend).array(:string)
        optional(:append).array(:string)
      end
    end

    class << self
      include Dry::Monads[:result]

      # Loads the config from XDG, Local Workspace, and Environment, in that order.
      # Returns the validated configuration hash wrapped in a Dry::Monads::Result.
      def load
        global_config = load_first_match(global_paths) || {}
        local_config = Norn::LocalConfigReader.new.read || {}

        config_data = {}
        config_data.merge!(global_config)
        config_data.merge!(local_config)

        # Merge instructions block customly
        global_inst = global_config[:instructions] || {}
        local_inst = local_config[:instructions] || {}
        compiled_inst = compile_instructions_block(global_inst, local_inst)
        config_data[:instructions] = compiled_inst

        # 3. Load Environment Variables
        if ENV["NORN_PROVIDER"] && !ENV["NORN_PROVIDER"].strip.empty?
          config_data[:llm_provider] = ENV["NORN_PROVIDER"].strip
        end

        # Normalize keys (e.g. map alias 'provider' to 'llm_provider')
        config_data = normalize_keys(config_data)

        # 4. Validate with dry-schema
        validation = Schema.call(config_data)
        if validation.success?
          # Apply validated values to dry-configurable Config
          validation.to_h.each do |key, value|
            Norn::Config.config.send("#{key}=", value) if value
          end
        else
          # Print validation warnings to stderr
          warn "Norn Config Warning: #{validation.errors.to_h.inspect}"
        end

        Success(validation.to_h)
      end

      private

      def global_paths
        config_home = ENV["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config")
        [
          File.join(config_home, "norn", "config.yml"),
          File.join(config_home, "norn", "config.yaml"),
          File.join(config_home, "norn", "config.json")
        ]
      end

      # Find first existing config file and load it
      def load_first_match(paths)
        paths.each do |path|
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
        nil
      end

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

      def normalize_keys(hash)
        if hash[:provider] && !hash[:llm_provider]
          hash[:llm_provider] = hash.delete(:provider)
        end
        hash
      end

      def compile_instructions_block(global_inst, local_inst)
        state = {
          clear: [],
          base: nil,
          prepend: [],
          append: []
        }

        [global_inst, local_inst].compact.each do |inst|
          # 1. Apply clear instructions
          if inst[:clear].is_a?(Array)
            clears = inst[:clear].map(&:to_s)
            state[:base] = nil if clears.include?("base")
            state[:prepend] = [] if clears.include?("prepend")
            state[:append] = [] if clears.include?("append")
            state[:clear] = (state[:clear] + clears).uniq
          end

          # 2. Merge new values at this level
          state[:base] = inst[:base] if inst.key?(:base) && !inst[:base].nil?
          
          if inst[:prepend].is_a?(Array)
            state[:prepend] += inst[:prepend]
          end

          if inst[:append].is_a?(Array)
            state[:append] += inst[:append]
          end
        end

        state
      end
    end
  end
end
