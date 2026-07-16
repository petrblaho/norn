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

      class IgnoreFilter
        DEFAULT_EXCLUDES = [
          '.git', 'node_modules', 'vendor/bundle', 'tmp', 'log', 'coverage', '.sass-cache'
        ].freeze

        def initialize(root_path)
          @root = File.expand_path(root_path)
          @patterns = []
          DEFAULT_EXCLUDES.each { |pat| add_pattern(pat) }
          
          gitignore_path = File.join(@root, '.gitignore')
          if File.exist?(gitignore_path)
            File.readlines(gitignore_path, encoding: "utf-8").each do |line|
              # Scrub out any bad encodings cleanly
              cleaned = line.force_encoding("UTF-8").scrub.strip
              next if cleaned.empty? || cleaned.start_with?('#')
              add_pattern(cleaned)
            end
          end
        end

        def ignored?(relative_path)
          path = relative_path.to_s.sub(%r{^\/}, '')
          @patterns.any? { |re| re.match?(path) }
        end

        private

        def add_pattern(pat)
          has_leading_slash = pat.start_with?('/')
          is_dir = pat.end_with?('/')
          
          # Strip trailing slash for matching
          clean_pat = pat.sub(%r{\/$}, '')
          
          # Check if there is any other slash in the pattern
          has_inline_slash = clean_pat.include?('/') && !clean_pat.start_with?('/')
          
          anchored = has_leading_slash || has_inline_slash
          
          # Now strip leading slash for compilation to relative path matches
          clean_pat = clean_pat.sub(%r{^\/}, '')

          escaped = Regexp.escape(clean_pat)
          escaped.gsub!('\*\*', '.*')
          escaped.gsub!('\*', '[^/]*')
          escaped.gsub!('\?', '[^/]')

          if anchored
            if is_dir
              regex_str = "^(#{escaped})(?:/.*)?$"
            else
              regex_str = "^(#{escaped})(?:/.*)?$"
            end
          else
            if is_dir
              regex_str = "(^|/)(#{escaped})(?:/.*)?$"
            else
              regex_str = "(^|/)(#{escaped})($|/)"
            end
          end

          @patterns << Regexp.new(regex_str)
        rescue => e
          # Gracefully ignore malformed patterns
        end
      end
    end
  end
end
