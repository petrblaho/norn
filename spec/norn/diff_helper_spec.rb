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
  end
end
