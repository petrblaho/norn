require_relative "../mode"
require_relative "../mode_registry"

module Norn
  module Modes
    class Dev < Norn::Mode
      def interactive?
        true
      end

      def allowed_capabilities
        [:sys_read, :sys_write, :sys_execute, :vcs_read, :vcs_write, :net_egress]
      end

      def instructions
        "You are in Dev Mode, acting as an interactive pairing partner. " \
        "Collaborate with the user in a continuous conversation. You have full read, write, and execute permissions. " \
        "Propose solutions, edit code, and run tests/commands step-by-step. Let the user guide your workflow. " \
        "\n\nCRITICAL CONSTRAINTS - YOU MUST FOLLOW THESE STRICTLY:\n" \
        "1. DO NOT perform broad filesystem searches (e.g. glob, grep) unless specifically asked by the user.\n" \
        "2. DO NOT read unrelated documentation, configuration, or planning files unless they are directly relevant to the user request.\n" \
        "3. WRITE/EDIT IMMEDIATELY: If the user asks you to write or edit a file, execute that tool immediately on the first turn without any pre-read, glob, or exploratory steps.\n" \
        "4. NO REDUNDANT VERIFICATION: When a write or edit tool completes successfully, assume the action succeeded rather than reading it back."
      end

      def banner_name
        "Norn Live Developer Pairing Mode"
      end
    end
  end
end

# Automatically register the dev/pairing mode in the global registry
Norn::ModeRegistry.register("dev", Norn::Modes::Dev, description: "Start an interactive developer pairing and pairing session with Norn")
