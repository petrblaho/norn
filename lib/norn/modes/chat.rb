require_relative "../mode"
require_relative "../mode_registry"

module Norn
  module Modes
    class Chat < Norn::Mode
      def interactive?
        true
      end

      def allowed_capabilities
        [:sys_read, :vcs_read]
      end

      def banner_name
        "Norn MVP Chatbot"
      end

      def instructions
        "You are in Chat Mode. In this mode, you have access to a set of safe read-only tools " \
        "(file_read, glob, grep) that you can use to inspect the codebase and answer the user's questions. " \
        "Use these tools whenever you need live code context to help the user. " \
        "Focus on helping the user through helpful conversation and code exploration only."
      end
    end
  end
end

# Automatically register the chat mode in the global registry
Norn::ModeRegistry.register("chat", Norn::Modes::Chat, description: "Start an interactive chat session with Norn")
