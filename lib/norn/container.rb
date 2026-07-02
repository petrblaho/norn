require "dry/system"

module Norn
  class Container < Dry::System::Container
    configure do |config|
      # Set the root of the system to the workspace root directory
      config.root = File.expand_path("../..", __dir__)

      # Configure directory auto-loading/registration
      config.component_dirs.add "lib" do |dir|
        # Register classes in Norn namespace without prefix (e.g. Norn::Chatbot as "chatbot")
        dir.namespaces.add "norn", key: nil
      end
    end
  end
end
