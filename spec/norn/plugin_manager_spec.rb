require "spec_helper"

RSpec.describe Norn::PluginManager do
  describe ".subscribe and .trigger" do
    it "allows subscribing to an event and triggers it with arguments" do
      triggered_args = nil
      described_class.subscribe(:test_event) do |*args|
        triggered_args = args
      end

      described_class.trigger(:test_event, "foo", "bar")
      expect(triggered_args).to eq(["foo", "bar"])
    end

    it "allows multiple subscribers to the same event" do
      calls = []
      described_class.subscribe(:multi) { calls << 1 }
      described_class.subscribe(:multi) { calls << 2 }

      described_class.trigger(:multi)
      expect(calls).to eq([1, 2])
    end

    it "supports mutating arguments passed by reference" do
      list = []
      described_class.subscribe(:modify) do |payload|
        payload << "hooked"
      end

      described_class.trigger(:modify, list)
      expect(list).to eq(["hooked"])
    end
  end
end
