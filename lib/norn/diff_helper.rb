require "set"

module Norn
  class DiffHelper
    # Generates a standard, beautifully colored unified diff preview
    # Red (\e[31m) for removals, Green (\e[32m) for additions
    def self.color_diff(old_content, new_content, context_size = 3)
      old_lines = old_content.to_s.split("\n", -1)
      new_lines = new_content.to_s.split("\n", -1)

      # Handle pure file creations cleanly
      if old_content.to_s.empty?
        return new_lines.map { |line| "\e[32m+ #{line}\e[0m" }.join("\n")
      end

      # 1. Align lines and map to line numbers
      diff_lines = []
      i = 0
      j = 0
      old_line_no = 1
      new_line_no = 1

      while i < old_lines.size || j < new_lines.size
        if i < old_lines.size && j < new_lines.size && old_lines[i] == new_lines[j]
          diff_lines << { type: :unchanged, text: old_lines[i], old_no: old_line_no, new_no: new_line_no }
          i += 1
          j += 1
          old_line_no += 1
          new_line_no += 1
        elsif j < new_lines.size && (i >= old_lines.size || !old_lines[i..-1].include?(new_lines[j]))
          diff_lines << { type: :added, text: new_lines[j], old_no: nil, new_no: new_line_no }
          j += 1
          new_line_no += 1
        elsif i < old_lines.size
          diff_lines << { type: :removed, text: old_lines[i], old_no: old_line_no, new_no: nil }
          i += 1
          old_line_no += 1
        else
          break
        end
      end

      # 2. Identify shown line indices based on context around changes
      shown_indices = Set.new
      diff_lines.each_with_index do |line, idx|
        if line[:type] != :unchanged
          start_idx = [0, idx - context_size].max
          end_idx = [diff_lines.size - 1, idx + context_size].min
          (start_idx..end_idx).each { |s| shown_indices << s }
        end
      end

      # 3. Group contiguous shown indices into hunks
      hunks = []
      current_hunk = []

      shown_indices.to_a.sort.each do |idx|
        if current_hunk.empty? || current_hunk.last == idx - 1
          current_hunk << idx
        else
          hunks << current_hunk
          current_hunk = [idx]
        end
      end
      hunks << current_hunk unless current_hunk.empty?

      # 4. Format each hunk with a standard unified diff header
      diff_output = []
      hunks.each do |hunk_indices|
        hunk_lines = hunk_indices.map { |idx| diff_lines[idx] }

        old_lines_in_hunk = hunk_lines.select { |l| l[:old_no] }
        old_start = old_lines_in_hunk.any? ? old_lines_in_hunk.first[:old_no] : 0
        old_count = old_lines_in_hunk.size

        new_lines_in_hunk = hunk_lines.select { |l| l[:new_no] }
        new_start = new_lines_in_hunk.any? ? new_lines_in_hunk.first[:new_no] : 0
        new_count = new_lines_in_hunk.size

        # Chunk header in cyan
        diff_output << "\e[36m@@ -#{old_start},#{old_count} +#{new_start},#{new_count} @@\e[0m"

        hunk_lines.each do |line|
          case line[:type]
          when :unchanged
            diff_output << "  #{line[:text]}"
          when :added
            diff_output << "\e[32m+ #{line[:text]}\e[0m"
          when :removed
            diff_output << "\e[31m- #{line[:text]}\e[0m"
          end
        end
      end

      diff_output.join("\n")
    end
  end
end
