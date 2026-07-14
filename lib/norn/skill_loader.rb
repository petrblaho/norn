require "fileutils"

module Norn
  class SkillLoader
    class << self
      # Scans project-level and user-level scopes for SKILL.md directories and registers them.
      def load_all
        # Gather search directories in order of lowest to highest precedence.
        # This allows higher-precedence (project-level) skills to override and shadow lower-precedence (user-level) skills.
        scan_paths = []

        # 1. User scope (lower precedence)
        home = begin
                 Dir.home
               rescue => e
                 nil
               end

        if home
          scan_paths << File.join(home, ".norn", "skills")
          scan_paths << File.join(home, ".agents", "skills")
        end

        # 2. Project/Workspace scope (higher precedence)
        scan_paths << File.join(Norn.workspace_root, ".norn", "skills")
        scan_paths << File.join(Norn.workspace_root, ".agents", "skills")

        scan_paths.uniq.each do |base_dir|
          next unless Dir.exist?(base_dir)

          # Scan for subdirectories containing SKILL.md
          Dir.glob(File.join(base_dir, "*")).each do |sub_dir|
            next unless File.directory?(sub_dir)

            # Avoid scanning noise/dependencies
            sub_dir_name = File.basename(sub_dir)
            next if [".git", "node_modules", "build", "tmp", "coverage"].include?(sub_dir_name)

            skill_file = File.join(sub_dir, "SKILL.md")
            if File.exist?(skill_file)
              skill = Norn::Skill.parse_file(skill_file)
              next unless skill

              # Check for collision and warn
              existing = Norn::SkillRegistry.resolve(skill.name)
              if existing
                warn "Norn Skill Loader Warning: Skill '#{skill.name}' at '#{skill.location}' is shadowing/overriding a previously loaded skill of the same name at '#{existing.location}'."
              end

              Norn::SkillRegistry.register(skill)
            end
          end
        end
      end
    end
  end
end
