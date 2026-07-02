require_relative "../mode"
require_relative "../mode_registry"
require_relative "../tool_registry"

module Norn
  module Modes
    class Task < Norn::Mode
      def interactive?
        false
      end

      def allowed_capabilities
        [:sys_read, :sys_write, :vcs_read, :vcs_write]
      end

      def banner_name
        "Norn Autonomous Task Agent"
      end

      def instructions
        "In Task Mode, you are a professional, autonomous software developer agent. " \
        "You have access to a set of highly specific tools. Work step-by-step using these tools to complete the user's task. " \
        "\n\nCRITICAL CONSTRAINTS - YOU MUST FOLLOW THESE STRICTLY:\n" \
        "1. DO NOT perform broad filesystem searches (e.g. glob, grep) unless the user's task is specifically about finding files.\n" \
        "2. DO NOT read unrelated documentation, configuration, or planning files. Only read files you are actively modifying.\n" \
        "3. WRITE IMMEDIATELY: If the user asks you to write or create a file, execute the file_write tool immediately on the first turn without any pre-read, glob, or exploratory steps.\n" \
        "4. NO REDUNDANT VERIFICATION: When a write tool completes successfully, assume the file was written and conclude the task immediately rather than reading it back."
      end
    end
  end
end

# Automatically register the task mode in the global registry
Norn::ModeRegistry.register("task", Norn::Modes::Task, description: "Run Norn in autonomous Task Mode to solve coding and system tasks")
