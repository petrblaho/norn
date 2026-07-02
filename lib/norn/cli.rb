require "dry/cli"

module Norn
  module CLI
    extend Dry::CLI::Registry

    # Dynamically build and register all modes as CLI commands on boot
    def self.register_plugins!
      # 1. Allow plugins to register custom modes in the ModeRegistry
      Norn::PluginManager.trigger(:on_mode_register, Norn::ModeRegistry)

      # 2. Allow legacy/custom direct CLI command registrations via plugins
      Norn::PluginManager.trigger(:on_cli_register, self)

      # 3. For each registered mode in Norn::ModeRegistry, dynamically build and register a Dry::CLI::Command
      Norn::ModeRegistry.registered_modes.each do |mode_name|
        desc = Norn::ModeRegistry.description_for(mode_name)
        command_class = define_mode_command(mode_name, desc)
        
        # Register command in dry-cli
        register mode_name, command_class
      end
    end

    # Factory method to dynamically define a Dry::CLI::Command subclass
    def self.define_mode_command(mode_name, description)
      Class.new(Dry::CLI::Command) do
        @mode_name = mode_name

        class << self
          attr_reader :mode_name
        end

        desc description
        argument :prompt, type: :string, required: false, desc: "An optional initial prompt or task"
        
        # Dynamically register all options defined in GlobalOptions
        Norn::GlobalOptions.registered_options.each do |name, opt|
          option name, type: opt[:type], desc: opt[:desc], aliases: opt[:aliases], default: opt[:default]
        end

        def call(prompt: nil, **options)
          # Apply provider override if specified
          if options[:provider]
            Norn.config.llm_provider = options[:provider]
          end

          # Propagate the debug flag to the process environment
          if options[:debug]
            ENV["NORN_DEBUG"] = "true"
          end

          mode_name = self.class.mode_name
          mode_class = Norn::ModeRegistry.resolve(mode_name)
          
          # Initialize the resolved mode and start its execution
          result = mode_class.new.start(prompt)

          # If the mode start returned a monadic Failure, handle and render it
          if result.respond_to?(:failure?) && result.failure?
            Norn::ErrorRenderer.render(result.failure)
            exit 1
          end

          result
        end
      end
    end
  end
end
