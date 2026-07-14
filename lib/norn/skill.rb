require "yaml"

module Norn
  class Skill
    attr_reader :name, :description, :triggers, :invocable, :argument_hint, :instructions, :location

    def initialize(name:, description:, triggers:, invocable:, argument_hint:, instructions:, location:)
      @name = name.to_s.strip
      @description = description.to_s.strip
      @triggers = Array(triggers).map { |t| t.to_s.strip.downcase }
      @invocable = !!invocable
      @argument_hint = argument_hint ? argument_hint.to_s.strip : nil
      @instructions = instructions.to_s.strip
      @location = location ? File.expand_path(location) : nil
    end

    # Return the parent directory of the skill file
    def base_directory
      return nil unless @location
      File.dirname(@location)
    end

    # Scan the base directory for supporting resources (all files excluding SKILL.md itself)
    def resources
      dir = base_directory
      return [] unless dir && Dir.exist?(dir)

      # Find all files recursively under the skill directory
      Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
        .select { |f| File.file?(f) }
        .map { |f| File.expand_path(f) }
        .reject { |f| File.basename(f) == "SKILL.md" }
        .map { |f| Pathname.new(f).relative_path_from(Pathname.new(dir)).to_s }
    end

    # Checks if a given text string matches any of the skill's triggers
    def matches?(text)
      normalized_text = text.to_s.downcase
      @triggers.any? do |trigger|
        normalized_text.include?(trigger)
      end
    end

    class << self
      def parse_file(filepath)
        return nil unless File.exist?(filepath)
        content = File.read(filepath)
        parse_content(content, filepath)
      end

      def parse_content(content, filepath = nil)
        # Match YAML frontmatter between --- and ---
        match = content.match(/\A---\s*\n(.*?)\n---\s*\n(.*)/m)
        unless match
          return nil
        end

        frontmatter_raw = match[1]
        body = match[2].strip

        frontmatter = nil
        begin
          frontmatter = YAML.safe_load(frontmatter_raw, permitted_classes: [Symbol, Date, Time])
        rescue => e
          # Retry with sanitized YAML
          begin
            sanitized = sanitize_malformed_yaml(frontmatter_raw)
            frontmatter = YAML.safe_load(sanitized, permitted_classes: [Symbol, Date, Time])
          rescue => e2
            warn "Norn Skill Parser Error: Failed to parse frontmatter YAML at #{filepath || 'string'}: #{e2.message}"
            return nil
          end
        end

        return nil unless frontmatter.is_a?(Hash)

        # Normalize keys (symbolize, downcase, substitute hyphens)
        normalized_fm = {}
        frontmatter.each do |k, v|
          norm_key = k.to_s.downcase.gsub("-", "_").to_sym
          normalized_fm[norm_key] = v
        end

        # Validation
        name = normalized_fm[:name]&.to_s&.strip
        description = normalized_fm[:description]&.to_s&.strip

        if name.nil? || name.empty?
          warn "Norn Skill Parser Warning: Skill is missing a 'name' field."
          return nil
        end

        if description.nil? || description.empty?
          warn "Norn Skill Parser Warning: Skill '#{name}' is missing a 'description' field."
          return nil
        end

        # Check directory name matches
        if filepath
          parent_dir_name = File.basename(File.dirname(filepath))
          if name != parent_dir_name
            warn "Norn Skill Parser Warning: Skill name '#{name}' does not match its parent directory name '#{parent_dir_name}'."
          end
        end

        new(
          name: name,
          description: description,
          triggers: normalized_fm[:triggers] || [],
          invocable: normalized_fm[:invocable],
          argument_hint: normalized_fm[:argument_hint] || normalized_fm[:argument_hint_hint], # handle various spellings
          instructions: body,
          location: filepath
        )
      end

      private

      # Preprocesses unquoted values containing colons to prevent Psych parsing errors
      def sanitize_malformed_yaml(yaml_str)
        sanitized_lines = []
        yaml_str.each_line do |line|
          stripped = line.strip
          if stripped =~ /^([a-zA-Z0-9_\-]+)\s*:\s*(.*)$/
            key = $1
            val = $2.strip
            # If the value contains a colon and is not already wrapped in quotes, wrap it
            if val.include?(":") && !((val.start_with?('"') && val.end_with?('"')) || (val.start_with?("'") && val.end_with?("'")))
              escaped_val = val.gsub('"', '\\"')
              line = "#{key}: \"#{escaped_val}\"\n"
            end
          end
          sanitized_lines << line
        end
        sanitized_lines.join
      end
    end
  end
end
