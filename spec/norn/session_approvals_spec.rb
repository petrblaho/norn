require "spec_helper"
require "norn/mode"
require "norn/ui/gatekeeper"

class SessionApprovalsMode < Norn::Mode
  def interactive?; true; end
  def allowed_capabilities; @allowed_capabilities ||= [:sys_execute, :vcs_read, :sys_read, :vcs_write, :net_egress]; end
  def instructions; "Do things"; end
  def banner_name; "Session Approvals Mode"; end
end

RSpec.describe "Session Approvals Integration" do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  let(:session) { Norn::Session.new }
  subject { SessionApprovalsMode.new(input: input, output: output) }

  before do
    allow(Norn).to receive(:[]).with("session").and_return(session)
    Norn::ToolRegistry.registered_tools.clear
    
    # Register a mock git tool
    Norn::ToolRegistry.register(
      Norn::Plugins::Git::GitTool.new("git", "Git", {}, required_capabilities: [:sys_execute]) { |args| "git executed" }
    )
  end

  it "bypasses prompts and executes if the session contains approval for the specific subcommand" do
    session.append(:session_approvals, { tool_name: "git", subcommand: "status" })
    
    result = subject.execute_tool("git", { subcommand: "status" })
    
    expect(result.success?).to be true
    expect(result.value!).to eq("git executed")
    expect(output.string).to include("⚡ Session approved: git")
  end

  it "forces a prompt if the session has approval for a different subcommand" do
    session.append(:session_approvals, { tool_name: "git", subcommand: "status" })
    
    gatekeeper = double("Gatekeeper")
    allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)
    
    # It should NOT auto-approve because "push" is dangerous and does not have specific approval
    expect(gatekeeper).to receive(:authorize_danger).and_return(true)
    
    result = subject.execute_tool("git", { subcommand: "push" })
    expect(result.success?).to be true
  end

  it "adds subcommand-specific approval to the session if the user selects the session option" do
    gatekeeper = double("Gatekeeper")
    allow(Norn::UI::Gatekeeper).to receive(:new).and_return(gatekeeper)
    
    # Simulate user selecting the :session option from the prompt
    expect(gatekeeper).to receive(:authorize_danger).and_return(:session)
    
    expect(session.get(:session_approvals)).to be_empty
    
    result = subject.execute_tool("git", { subcommand: "push" })
    expect(result.success?).to be true
    
    # Verify approval was added to session
    expect(session.get(:session_approvals)).to contain_exactly({ tool_name: "git", subcommand: "push" })
  end
end
