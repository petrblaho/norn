require "spec_helper"
require "norn/tool"
require "norn/mode"

RSpec.describe "PromptUserPlugin and prompt_user tool", norn_plugins: :prompt_user do
  before do
    Norn::ToolRegistry.clear!
    Norn::PluginManager.trigger(:on_tool_register, Norn::ToolRegistry)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  let(:tool) { Norn::ToolRegistry.resolve("prompt_user") }

  it "registers successfully in the ToolRegistry with correct capabilities and system instructions" do
    expect(tool).not_to be_nil
    expect(tool.required_capabilities).to eq([:sys_read])
    expect(tool.system_instructions).to include("If a user instruction is ambiguous")
  end

  describe "In-flight Execution with Context" do
    context "when running in an Interactive Mode" do
      it "handles confirm prompts successfully returning 'yes'" do
        io = norn_io("y")
        interactive_mode = Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: io.input, output: io.output)

        result_str = tool.call({ type: "confirm", question: "Apply changes?" }, interactive_mode)
        expect(result_str).to eq("yes")
      end

      it "handles select single-option prompts successfully" do
        # Simulate selecting the first option (pressing enter)
        io = norn_io("")
        interactive_mode = Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: io.input, output: io.output)

        result_str = tool.call({ type: "select", question: "Choose one:", choices: ["option_a", "option_b"] }, interactive_mode)
        expect(result_str).to eq("option_a")
        expect(io).to have_produced("Use arrow keys, Enter to select")
      end

      it "handles select with allow_custom: true, dynamically prompting for custom text when 'Custom' option is chosen" do
        # Simulate moving down twice using "\e[B" key sequences, pressing Enter, then typing custom text
        io = norn_io("\e[B\e[B\nMy custom value\n")
        
        interactive_mode = Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: io.input, output: io.output)

        result_str = tool.call({
          type: "select",
          question: "Choose one:",
          choices: ["option_a", "option_b"],
          allow_custom: true,
          custom_prompt: "Type custom value:"
        }, interactive_mode)

        expect(result_str).to eq("My custom value")
        expect(io).to have_produced("Type custom value:")
        expect(io).to have_produced("Use arrow keys, Enter to select")
      end

      it "handles multi_select checklist prompts successfully and renders help text guidelines" do
        # Simulate space bar toggling option, then enter submitting
        io = norn_io(" \n")
        
        interactive_mode = Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: io.input, output: io.output)

        result_str = tool.call({ type: "multi_select", question: "Languages:", choices: ["Ruby", "Go"] }, interactive_mode)
        expect(result_str).to eq("Ruby")
        expect(io).to have_produced("Press Space to toggle options, Enter to submit")
      end

      it "handles input text prompts successfully" do
        io = norn_io("Custom Answer")
        interactive_mode = Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; true; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(input: io.input, output: io.output)

        result_str = tool.call({ type: "input", question: "Enter text:" }, interactive_mode)
        expect(result_str).to eq("Custom Answer")
      end
    end

    context "when running in a Non-Interactive Mode" do
      let(:io) { norn_io }
      let(:non_interactive_mode) do
        Class.new(Norn::Mode) do
          def start(prompt = nil); end
          def interactive?; false; end
          def allowed_capabilities; [:sys_read]; end
          def instructions; "test"; end
        end.new(output: io.output)
      end

      it "falls back to default_value safely if provided" do
        result_str = tool.call({ type: "confirm", question: "Apply?", default_value: "yes" }, non_interactive_mode)
        expect(result_str).to eq("Non-interactive session fallback: yes")
      end

      it "raises a runtime error if no default_value is provided" do
        expect {
          tool.call({ type: "confirm", question: "Apply?" }, non_interactive_mode)
        }.to raise_error(RuntimeError, /Interactive prompting is not supported/)
      end
    end
  end
end
