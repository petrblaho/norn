$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "norn"
Norn::PluginLoader.load_all

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Reset config and plugin manager before each example to keep tests isolated
  config.before(:each) do
    Norn::PluginManager.reset!
    Norn::Config.config.update(
      llm_provider: "openai",
      sandbox_info: "You are running in a secure sandboxed CLI environment."
    )
  end

  # Require and load our plugin helper *after* the global before(:each) hook
  # so that the metadata setup runs after the global plugin reset.
  require_relative "support/norn_plugins_helper"
  require_relative "support/norn_llm_helper"
end
