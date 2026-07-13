require "spec_helper"

RSpec.describe Norn::Tool do
  describe "#call" do
    it "recursively sanitizes string outputs to valid UTF-8" do
      binary_str = "invalid \xFF character".b
      tool = Norn::Tool.new("test_tool", "desc", {}) { binary_str }

      result = tool.call({})
      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result.valid_encoding?).to be(true)
    end

    it "recursively sanitizes strings inside nested hashes and arrays" do
      binary_str = "binary \xFF".b
      nested_data = {
        key: binary_str,
        list: [binary_str, { deep_key: binary_str }]
      }
      tool = Norn::Tool.new("nested_tool", "desc", {}) { nested_data }

      result = tool.call({})
      
      expect(result[:key].encoding).to eq(Encoding::UTF_8)
      expect(result[:key].valid_encoding?).to be(true)
      
      expect(result[:list][0].encoding).to eq(Encoding::UTF_8)
      expect(result[:list][0].valid_encoding?).to be(true)
      
      expect(result[:list][1][:deep_key].encoding).to eq(Encoding::UTF_8)
      expect(result[:list][1][:deep_key].valid_encoding?).to be(true)
    end

    it "leaves non-string objects untouched" do
      tool = Norn::Tool.new("numeric_tool", "desc", {}) { 42 }
      expect(tool.call({})).to eq(42)
    end
  end
end
