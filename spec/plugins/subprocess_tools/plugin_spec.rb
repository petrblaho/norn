require "spec_helper"
require "norn/plugin_manager"
require "norn/tool_registry"
require_relative "../../../plugins/subprocess_tools/plugin"

RSpec.describe SubprocessToolsPlugin, norn_plugins: :subprocess_tools do
  let(:registry) { Norn::ToolRegistry }

  before do
    Norn::PluginManager.reset!
    Norn::PluginManager.register_core_hooks!
    Norn::ToolRegistry.clear!
    
    # Setup persistent subshell
    @subshell = Norn::Execution::Subshell.new
    allow(Norn::Container).to receive(:[]).and_call_original
    allow(Norn::Container).to receive(:[]).with("subprocess.shell").and_return(@subshell)
    
    plugin = described_class.new
    plugin.on_boot(Norn::Container)
    plugin.on_tool_register(registry)
  end

  after do
    @subshell.stop if @subshell.started?
    Norn::ToolRegistry.clear!
  end

  it "registers the execute_command tool" do
    expect(registry.resolve("execute_command")).not_to be_nil
    expect(registry.resolve("execute_command").required_capabilities).to eq([:sys_execute])
    expect(registry.resolve("execute_command").dangerous?).to be(true)
  end

  it "executes a safe command and returns the text result" do
    tool = registry.resolve("execute_command")
    result = tool.call({ command: "echo 'plugin execution'" }, nil)
    expect(result.strip).to eq("plugin execution")
  end

  it "raises security error on blacklisted inputs" do
    tool = registry.resolve("execute_command")
    expect {
      tool.call({ command: "sudo rm -rf /" }, nil)
    }.to raise_error(SecurityError)
  end

  it "retains environment and directory states across tool runs" do
    tool = registry.resolve("execute_command")
    
    # Shift directories in turn 1
    tool.call({ command: "cd lib" }, nil)
    
    # Check directory in turn 2
    outcome = tool.call({ command: "pwd" }, nil)
    expect(outcome).to include("lib")
  end

  it "emits real-time progress events over :on_subprocess_output hook" do
    tool = registry.resolve("execute_command")
    emitted_events = []

    Norn::PluginManager.subscribe(:on_subprocess_output) do |payload|
      emitted_events << payload
    end

    tool.call({ command: "echo 'trigger hook'" }, nil)
    expect(emitted_events.any? { |e| e[:chunk].include?("trigger hook") }).to be true
  end
end
