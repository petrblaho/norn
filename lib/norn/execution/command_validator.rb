module Norn
  module Execution
    class CommandValidator
      BLACKLIST = [
        [/\bsudo\b/i, "Prevent root privilege escalation!"],
        [/rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\//, "Prevent destructive rm -rf / commands!"],
        [/rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\*/, "Prevent destructive rm -rf * workspace wipes!"],
        [/rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\./, "Prevent destructive rm -rf . current folder wipes!"],
        [/>\s*\/dev\/(?:sda|sdb|nvme)/, "Prevent destructive raw disk blocks writing!"],
        [/\bdd\b.*if=.*of=\/dev\//, "Prevent destructive raw device block copies!"]
      ].freeze

      def self.validate!(command)
        BLACKLIST.each do |pattern, message|
          if command =~ pattern
            raise SecurityError, "Execution Blocked: #{message}"
          end
        end
        nil
      end
    end
  end
end
