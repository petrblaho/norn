require "spec_helper"
require "norn/diff_helper"

RSpec.describe Norn::DiffHelper do
  describe ".color_diff" do
    it "renders pure additions in green when old content is empty" do
      old_content = ""
      new_content = "line 1\nline 2"

      diff = described_class.color_diff(old_content, new_content)
      
      expect(diff).to include("\e[32m+ line 1\e[0m")
      expect(diff).to include("\e[32m+ line 2\e[0m")
    end

    it "renders removed lines in red, added in green, and matching lines as normal context" do
      old_content = "line_a\nline_b\nline_c"
      new_content = "line_a\nline_d\nline_c"

      diff = described_class.color_diff(old_content, new_content)

      expect(diff).to include("  line_a")
      expect(diff).to include("\e[31m- line_b\e[0m")
      expect(diff).to include("\e[32m+ line_d\e[0m")
      expect(diff).to include("  line_c")
    end

    it "only shows the changed lines and their context, omitting distant unchanged lines" do
      old_content = (1..20).map { |n| "line #{n}" }.join("\n")
      # Change line 10
      new_content = (1..20).map { |n| n == 10 ? "line 10 CHANGED" : "line #{n}" }.join("\n")

      diff = described_class.color_diff(old_content, new_content, 2) # context_size = 2

      # Should show cyan hunk header
      expect(diff).to include("\e[36m@@")

      # Should show changed line and its context (lines 8, 9, 10, 11, 12)
      expect(diff).to include("  line 8")
      expect(diff).to include("  line 9")
      expect(diff).to include("\e[31m- line 10\e[0m")
      expect(diff).to include("\e[32m+ line 10 CHANGED\e[0m")
      expect(diff).to include("  line 11")
      expect(diff).to include("  line 12")

      # Should NOT show lines outside the context (e.g. line 1, line 20)
      expect(diff).not_to include("  line 1\n")
      expect(diff).not_to include("  line 2\n")
      expect(diff).not_to include("  line 19\n")
    end
  end
end
