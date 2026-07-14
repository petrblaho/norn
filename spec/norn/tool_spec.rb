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

  describe "Session Approval Contract" do
    let(:tool) { Norn::Tool.new("dummy", "A dummy tool", {}) { "ok" } }
    let(:session) { double("Session") }

    it "provides a default session approval label" do
      expect(tool.session_approval_label({})).to eq("Approve 'dummy' for the rest of this session")
    end

    it "provides a default session approval pattern" do
      expect(tool.session_approval_pattern({})).to eq({ tool_name: "dummy" })
    end

    it "returns false for session_approved? if session is nil" do
      expect(tool.session_approved?(nil, {})).to be false
    end

    it "returns true if the session contains the approval and tool is not dangerous" do
      allow(session).to receive(:get).with(:session_approvals).and_return([{ tool_name: "dummy" }])
      expect(tool.session_approved?(session, {})).to be true
    end

    it "returns false if the tool is dangerous even if the session contains the approval" do
      allow(session).to receive(:get).with(:session_approvals).and_return([{ tool_name: "dummy" }])
      allow(tool).to receive(:dangerous?).and_return(true)
      expect(tool.session_approved?(session, {})).to be false
    end

    describe "allow_session_danger?" do
      it "defaults to true if the tool is statically dangerous" do
        dangerous_tool = Norn::Tool.new("danger", "desc", {}, dangerous: true) { "ok" }
        expect(dangerous_tool.allow_session_danger?).to be true
      end

      it "defaults to false if the tool is not statically dangerous" do
        safe_tool = Norn::Tool.new("safe", "desc", {}, dangerous: false) { "ok" }
        expect(safe_tool.allow_session_danger?).to be false
      end
    end

    describe "session_approved? with statically dangerous tool" do
      let(:dangerous_tool) { Norn::Tool.new("danger", "desc", {}, dangerous: true) { "ok" } }

      it "returns true if the session contains the approval and the tool allows session danger" do
        allow(session).to receive(:get).with(:session_approvals).and_return([{ tool_name: "danger" }])
        expect(dangerous_tool.session_approved?(session, {})).to be true
      end
    end
  end
end
