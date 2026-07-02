module Norn
  class DiffHelper
    # Generates a standard, beautifully colored unified diff preview
    # Red (\e[31m) for removals, Green (\e[32m) for additions
    def self.color_diff(old_content, new_content)
      old_lines = old_content.to_s.split("\n", -1)
      new_lines = new_content.to_s.split("\n", -1)

      # Handle pure file creations cleanly
      if old_content.to_s.empty?
        return new_lines.map { |line| "\e[32m+ #{line}\e[0m" }.join("\n")
      end

      diff_output = []
      i = 0
      j = 0

      # Dynamic LCS alignment scanner
      while i < old_lines.size || j < new_lines.size
        if i < old_lines.size && j < new_lines.size && old_lines[i] == new_lines[j]
          # Unchanged line (Context)
          diff_output << "  #{old_lines[i]}"
          i += 1
          j += 1
        elsif j < new_lines.size && (i >= old_lines.size || !old_lines[i..-1].include?(new_lines[j]))
          # Added line (Green)
          diff_output << "\e[32m+ #{new_lines[j]}\e[0m"
          j += 1
        elsif i < old_lines.size
          # Removed line (Red)
          diff_output << "\e[31m- #{old_lines[i]}\e[0m"
          i += 1
        else
          break
        end
      end

      diff_output.join("\n")
    end
  end
end
