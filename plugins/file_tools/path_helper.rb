module Norn
  module Plugins
    module FileTools
      module PathHelper
        def self.resolve_and_verify(relative_path)
          root = File.expand_path(Norn.workspace_root)
          # Expand the absolute path
          absolute_path = File.expand_path(relative_path, root)
          
          # Verify the path is inside the root directory
          unless absolute_path == root || absolute_path.start_with?(root + File::SEPARATOR)
            # Allow paths inside the base directory of any registered skill
            is_inside_skill = Norn::SkillRegistry.registered_skills.any? do |skill|
              next unless skill.base_directory
              skill_dir = File.expand_path(skill.base_directory)
              absolute_path == skill_dir || absolute_path.start_with?(skill_dir + File::SEPARATOR)
            end

            unless is_inside_skill
              raise SecurityError, "Path traversal attempt detected: #{relative_path} is outside the workspace root."
            end
          end

          absolute_path
        end
      end
    end
  end
end
