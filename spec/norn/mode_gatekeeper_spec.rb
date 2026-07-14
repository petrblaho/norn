require "spec_helper"
require "norn/mode"
require "norn/ui/gatekeeper"

# Define concrete dummy class to test abstract Mode integration
class DummyMode < Norn::Mode
  def interactive?; true; end
  def allowed_capabilities; @allowed_capabilities ||= []; end
  def instructions; "Do things"; end
  def banner_name; "Dummy Mode"; end
end

RSpec.describe "Mode Gatekeeper Integration" do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  subject { DummyMode.new(input: input, output: output) }

  before do
    # Register a dangerous tool requiring capabilities
    Norn::ToolRegistry.registered_tools.clear
    Norn::ToolRegistry.register(Norn::Tool.new(
      "write_secret", "Write a secret file", { type: "object", properties: { secret: { type: "string" } } },
      required_capabilities: [:sys_write], dangerous: true
    ) { |args| "Secret written: #{args[:secret]}" })
  end

  it "handles skip, edit loops, and success integration" do
    # Initialize our gatekeeper mock
    gatekeeper = double("Norn::UI::Gatekeeper")
    allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)

    # 1. First capability escalation check fails/unauthorized, user triggers edit
    expect(gatekeeper).to receive(:authorize_capabilities).and_return(false)
    expect(gatekeeper).to receive(:show_fallback_menu).and_return(:edit)
    expect(gatekeeper).to receive(:show_fallback_menu).never # should break into edit flow first
    
    # Simulate LLM client and feedback prompting
    client = double("LLMClient")
    allow(Norn::Container).to receive(:[]).and_wrap_original do |m, *args|
      args[0] == "llm.openai" ? client : m.call(*args)
    end
    allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("change secret to banana")
    
    # Mock LLM refinement returning updated symbolized parameters
    expect(gatekeeper).to receive(:refine_arguments).and_return(Dry::Monads::Success({ secret: "banana" }))

    # 2. Recurses! Now with updated arguments. Capability authorizes this time (allowed list modified in first run, or mock success)
    expect(gatekeeper).to receive(:authorize_capabilities).and_return(true)
    
    # 3. Danger guard is triggered. User selects Yes.
    expect(gatekeeper).to receive(:authorize_danger).and_return(true)

    result = subject.execute_tool("write_secret", { secret: "apple" })
    expect(result.success?).to be true
    expect(result.value!).to eq("Secret written: banana")
  end

  it "returns success and tells LLM when skipped by user request" do
    gatekeeper = double("Norn::UI::Gatekeeper")
    allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)

    expect(gatekeeper).to receive(:authorize_capabilities).and_return(false)
    expect(gatekeeper).to receive(:show_fallback_menu).and_return(:skip)

    result = subject.execute_tool("write_secret", { secret: "apple" })
    expect(result.success?).to be true
    expect(result.value!).to eq("Tool execution skipped by user request.")
  end
end
