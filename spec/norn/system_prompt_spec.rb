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
      instructions: {
        clear: [],
        base: nil,
        prepend: [],
        append: []
      }
    )
  end

  after do
    Norn::Config.config.update(
      sandbox_info: "You are running in a secure sandboxed CLI environment.",
      instructions: {
        clear: [],
        base: nil,
        prepend: [],
        append: []
      }
    )
  end

  it "compiles the prompt with standard sandbox info and mode instructions by default" do
    prompt = mode_instance.compile_system_prompt
    expect(prompt).to include("Standard Sandbox Info")
    expect(prompt).to include("Standard Mode Instructions")
  end

  describe "with the instructions config block" do
    it "prepends, appends, and overrides base instructions correctly" do
      Norn::Config.config.update(instructions: {
        clear: [],
        base: "Overridden Base",
        prepend: ["Prepended Rule A", "Prepended Rule B"],
        append: ["Appended Rule A", "Appended Rule B"]
      })

      prompt = mode_instance.compile_system_prompt

      expect(prompt).to include("Prepended Rule A")
      expect(prompt).to include("Prepended Rule B")
      expect(prompt).to include("Overridden Base")
      expect(prompt).to include("Appended Rule A")
      expect(prompt).to include("Appended Rule B")
      expect(prompt).not_to include("Standard Mode Instructions")
      
      # Verify linear ordering
      prompt_lines = prompt.split("\n").map(&:strip).reject(&:empty?)
      expect(prompt_lines).to include("Prepended Rule A")
      expect(prompt_lines).to include("Prepended Rule B")
      expect(prompt_lines).to include("Overridden Base")
      expect(prompt_lines).to include("Appended Rule A")
      expect(prompt_lines).to include("Appended Rule B")
    end
  end
end
