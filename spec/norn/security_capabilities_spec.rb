require "spec_helper"
require "norn/mode"
require "norn/tool"
require "norn/errors"
require "stringio"

RSpec.describe "Capability-Based Security Gatekeeper" do
  let(:test_tool) do
    Norn::Tool.new(
      "write_secret",
      "Write secret",
      { type: "object" },
      required_capabilities: [:sys_write]
    ) { "Success!" }
  end

  before do
    Norn::ToolRegistry.clear!
    Norn::ToolRegistry.register(test_tool)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  describe "Non-Interactive Mode (Block-by-Default)" do
    let(:output) { StringIO.new }
    let(:non_interactive_mode) do
      Class.new(Norn::Mode) do
        def start(prompt = nil); end
        def interactive?; false; end
        def allowed_capabilities; [:sys_read]; end # does not have sys_write
        def instructions; "test"; end
      end.new(output: output)
    end

    it "instantly blocks unauthorized tools and returns a monadic Failure" do
      result = non_interactive_mode.execute_tool("write_secret", {})

      expect(result).to be_failure
      expect(result.failure).to be_a(Norn::FailurePayload)
      expect(result.failure.message).to include("Security violation: Unauthorized capabilities requested")
      expect(output.string).to include("Security Block: Tool 'write_secret' requires sys_write")
    end
  end

  describe "Interactive Mode (User Prompt Escalation)" do
    let(:output) { StringIO.new }

    context "when user authorizes the escalation (y/yes)" do
      let(:input) { StringIO.new("y\n") }
      let(:interactive_mode) do
        Class.new(Norn::Mode) do
          attr_accessor :caps
          def initialize(input:, output:)
            super
            @caps = [:sys_read]
          end
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; @caps; end
          def instructions; "test"; end
        end.new(input: input, output: output)
      end

      it "prompts the user, temporarily adds capabilities to session, and executes the tool successfully" do
        result = interactive_mode.execute_tool("write_secret", {})

        expect(result).to be_success
        expect(result.value!).to eq("Success!")
        expect(output.string).to include("Security Escalation: Tool 'write_secret' requested unauthorized capabilities: sys_write")
        expect(output.string).to include("Operation authorized by user.")
        expect(interactive_mode.allowed_capabilities).to include(:sys_write)
      end
    end

    context "when user denies the escalation (n/no)" do
      let(:input) { StringIO.new("n\n") }
      let(:interactive_mode) do
        Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: input, output: output)
      end

      it "prompts the user, blocks execution, and returns a monadic Failure" do
        result = interactive_mode.execute_tool("write_secret", {})

        expect(result).to be_failure
        expect(result.failure.message).to include("Authorization denied by user")
        expect(output.string).to include("Operation blocked by user.")
      end
    end
  end
end
