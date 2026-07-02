require "spec_helper"

RSpec.describe Norn::ToolRegistry do
  before do
    described_class.clear!
  end

  after do
    described_class.clear!
  end

  describe ".register and .resolve" do
    it "allows registering a tool and resolving it by name" do
      tool = Norn::Tool.new("test_tool", "A test tool", { type: "object" }) { |args| "Result: #{args[:val]}" }
      described_class.register(tool)

      resolved = described_class.resolve("test_tool")
      expect(resolved).to eq(tool)
      expect(resolved.call({ val: 42 })).to eq("Result: 42")
    end

    it "lists all registered tools" do
      tool1 = Norn::Tool.new("t1", "desc", {}) { "t1" }
      tool2 = Norn::Tool.new("t2", "desc", {}) { "t2" }

      described_class.register(tool1)
      described_class.register(tool2)

      expect(described_class.registered_tools).to contain_exactly(tool1, tool2)
    end
  end
end
