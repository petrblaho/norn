require "spec_helper"
require_relative "../../../plugins/subprocess_tools/plugin"

RSpec.describe SubprocessToolsPlugin, norn_plugins: :subprocess_tools do
  let(:registry) { Norn::ToolRegistry }

  before do
    Norn::ToolRegistry.clear!
    Norn::PluginManager.trigger(:on_tool_register, Norn::ToolRegistry)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  it "registers the execute_command tool correctly" do
    tool = registry.resolve("execute_command")
    expect(tool).not_to be_nil
    expect(tool.required_capabilities).to eq([:sys_execute])
    expect(tool.dangerous?).to be(true)
  end

  it "executes a safe command and returns the text result" do
    tool = registry.resolve("execute_command")
    result = tool.call(command: "echo 'plugin execution'")
    expect(result.strip).to eq("plugin execution")
  end

  it "raises security error and triggers monad failure on blacklisted inputs" do
    tool = registry.resolve("execute_command")
    expect {
      tool.call(command: "sudo rm -rf /")
    }.to raise_error(SecurityError)
  end
end
