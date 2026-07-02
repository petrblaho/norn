require "dotenv"
Dotenv.load # Load environment variables from .env file if present

require "dry/monads"
require "dry/monads/do"
require_relative "norn/secret_scrubber"
require_relative "norn/global_options"
require_relative "norn/errors"
require_relative "norn/error_renderer"

require_relative "norn/container"
require_relative "norn/plugin"
require_relative "norn/plugin_manager"
require_relative "norn/plugin_loader"
require_relative "norn/mode"
require_relative "norn/mode_registry"
require_relative "norn/tool"
require_relative "norn/tool_registry"
require_relative "norn/modes/chat"
require_relative "norn/modes/task"
require_relative "norn/modes/dev"
require_relative "norn/cli"
require_relative "norn/config"
require_relative "norn/config_loader"

module Norn
  # A simple helper to access registered dependencies from our container
  def self.[](key)
    Container[key]
  end

  def self.config
    Config.config
  end

  def self.configure
    yield(Config.config)
  end
end
