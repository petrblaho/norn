require "spec_helper"
require "norn/mode"

RSpec.describe "Dynamic System Prompt Compilation" do
  let(:mock_mode_class) do
    Class.new(Norn::Mode) do
      def start(prompt = nil); end
      def interactive?; true; end
      def allowed_capabilities; []; end
      def banner_name; "Mock Mode"; end
      def instructions
        "Standard Mode Instructions"
      end
    end
  end

  let(:mode_instance) { mock_mode_class.new }

  before do
    Norn::Config.config.update(
      sandbox_info: "Standard Sandbox Info",
      instructions_override: nil,
      custom_instructions: nil
    )
  end

  after do
    Norn::Config.config.update(
      sandbox_info: "You are running in a secure sandboxed CLI environment.",
      instructions_override: nil,
      custom_instructions: nil
    )
  end

  it "compiles the prompt with standard sandbox info and mode instructions by default" do
    prompt = mode_instance.compile_system_prompt
    expect(prompt).to include("Standard Sandbox Info")
    expect(prompt).to include("Standard Mode Instructions")
  end

  it "fully overrides the mode instructions when instructions_override is specified" do
    Norn::Config.config.update(instructions_override: "Completely Overridden Instructions")
    prompt = mode_instance.compile_system_prompt

    expect(prompt).to include("Standard Sandbox Info")
    expect(prompt).to include("Completely Overridden Instructions")
    expect(prompt).not_to include("Standard Mode Instructions")
  end

  it "appends custom instructions when custom_instructions is specified" do
    Norn::Config.config.update(custom_instructions: "Appended Custom Rule")
    prompt = mode_instance.compile_system_prompt

    expect(prompt).to include("Standard Sandbox Info")
    expect(prompt).to include("Standard Mode Instructions")
    expect(prompt).to include("Appended Custom Rule")
  end
end
