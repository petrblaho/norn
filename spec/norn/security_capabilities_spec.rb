require "spec_helper"
require "norn/mode"
require "norn/tool"
require "norn/errors"

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
    let(:io) { norn_io }
    let(:non_interactive_mode) do
      Class.new(Norn::Mode) do
        def start(prompt = nil); end
        def interactive?; false; end
        def allowed_capabilities; [:sys_read]; end # does not have sys_write
        def instructions; "test"; end
      end.new(output: io.output)
    end

    it "instantly blocks unauthorized tools and returns a monadic Failure" do
      result = non_interactive_mode.execute_tool("write_secret", {})

      expect(result).to be_failure
      expect(result.failure).to be_a(Norn::FailurePayload)
      expect(result.failure.message).to include("Security violation: Unauthorized capabilities requested")
      expect(io).to have_produced("Security Block: Tool 'write_secret' requires sys_write")
    end
  end

  describe "Interactive Mode (User Prompt Escalation)" do
    context "when user authorizes the escalation (y/yes)" do
      let(:io) { norn_io("y") }
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
        end.new(input: io.input, output: io.output)
      end

      it "prompts the user, temporarily adds capabilities to session, and executes the tool successfully" do
        expect_any_instance_of(TTY::Prompt).to receive(:select).and_return(true)
        result = interactive_mode.execute_tool("write_secret", {})

        expect(result).to be_success
        expect(result.value!).to eq("Success!")
        expect(io).to have_produced_in_order(
          "Security Escalation: Tool 'write_secret' requested unauthorized capabilities: sys_write",
          "Operation authorized by user."
        )
        expect(interactive_mode.allowed_capabilities).to include(:sys_write)
      end
    end

    context "when user denies the escalation (n/no)" do
      let(:io) { norn_io("n") }
      let(:interactive_mode) do
        Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: io.input, output: io.output)
      end

      it "prompts the user, blocks execution, and returns a monadic Failure" do
        expect_any_instance_of(TTY::Prompt).to receive(:select).with("Do you want to authorize this operation?", any_args).and_return(false)
        expect_any_instance_of(TTY::Prompt).to receive(:select).with("\nOperation Aborted. What would you like to do next?", any_args).and_return(:abort)
        result = interactive_mode.execute_tool("write_secret", {})

        expect(result).to be_failure
        expect(result.failure.message).to include("Action aborted by user")
        expect(io).to have_produced("Operation blocked by user.")
      end
    end
  end
end
