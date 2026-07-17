require "spec_helper"

RSpec.describe GitPlugin, norn_plugins: :git do
  let(:registry) { Norn::ToolRegistry }

  before do
    Norn::ToolRegistry.clear!
    Norn::PluginManager.trigger(:on_tool_register, registry)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  describe "Plugin configuration" do
    it "defines the correct plugin name" do
      expect(described_class.plugin_name).to eq("git")
    end

    it "subclasses Norn::Plugin" do
      expect(described_class.ancestors).to include(Norn::Plugin)
    end
  end

  describe "#on_tool_register" do
    it "registers the git tool in the global ToolRegistry" do
      git_tool = registry.resolve("git")

      expect(git_tool).not_to be_nil
      expect(git_tool.name).to eq("git")
      expect(git_tool).to be_a(Norn::Plugins::Git::GitTool)
    end
  end

  describe "Dynamic Parametric Capabilities" do
    let(:tool) do
      Norn::Plugins::Git::GitTool.new(
        "git",
        "desc",
        {}
      )
    end

    it "returns read-only capabilities for status, diff, and log" do
      expect(tool.capabilities_for(subcommand: "status")).to contain_exactly(:vcs_read, :sys_read)
      expect(tool.capabilities_for(subcommand: "diff")).to contain_exactly(:vcs_read, :sys_read)
      expect(tool.capabilities_for(subcommand: "log")).to contain_exactly(:vcs_read, :sys_read)
    end

    it "returns write capabilities for add, commit, and checkout" do
      expect(tool.capabilities_for(subcommand: "add")).to contain_exactly(:vcs_write, :sys_write)
      expect(tool.capabilities_for(subcommand: "commit")).to contain_exactly(:vcs_write, :sys_write)
      expect(tool.capabilities_for(subcommand: "checkout")).to contain_exactly(:vcs_write, :sys_write)
    end

    it "returns network capabilities for pull, push, and fetch" do
      expect(tool.capabilities_for(subcommand: "push")).to contain_exactly(:vcs_write, :net_egress)
      expect(tool.capabilities_for(subcommand: "fetch")).to contain_exactly(:vcs_write, :net_egress)
    end

    it "defaults to sys_execute for unknown commands" do
      expect(tool.capabilities_for(subcommand: "unrecognized")).to contain_exactly(:sys_execute)
    end

    it "returns git subcommand session approval label" do
      expect(tool.session_approval_label(subcommand: "commit")).to eq("Approve 'git commit' for the rest of this session")
      expect(tool.session_approval_label({})).to eq("Approve 'git' for the rest of this session")
    end
  end

  describe "Parametric Danger Guard Evaluation" do
    let(:tool) do
      Norn::Plugins::Git::GitTool.new(
        "git",
        "desc",
        {}
      )
    end

    it "classifies status and diff as safe" do
      expect(tool.dangerous?(subcommand: "status")).to be false
      expect(tool.dangerous?(subcommand: "diff")).to be false
    end

    it "classifies commit and push as dangerous" do
      expect(tool.dangerous?(subcommand: "commit")).to be true
      expect(tool.dangerous?(subcommand: "push")).to be true
    end

    it "classifies safe checkout branches as safe" do
      expect(tool.dangerous?(subcommand: "checkout", arguments: ["my-feature-branch"])).to be false
    end

    it "classifies destructive checkout discard operations as dangerous" do
      expect(tool.dangerous?(subcommand: "checkout", arguments: ["."])).to be true
      expect(tool.dangerous?(subcommand: "checkout", arguments: ["--", "lib/norn.rb"])).to be true
      expect(tool.dangerous?(subcommand: "checkout", arguments: ["-f"])).to be true
    end

    it "classifies hard reset as dangerous" do
      expect(tool.dangerous?(subcommand: "reset", arguments: ["--hard", "HEAD~1"])).to be true
    end

    describe "#allow_session_danger?" do
      it "returns false so dangerous git subcommands still prompt" do
        expect(tool.allow_session_danger?).to be false
      end
    end
  end

  describe "Mocked command execution" do
    it "executes command using array parameter capture without shell wrappers" do
      git_tool = registry.resolve("git")
      
      expect(Open3).to receive(:capture3).with("git", "status", "-s", chdir: anything).and_return([" M lib/norn.rb", "", double(success?: true)])
      
      res = git_tool.call(subcommand: "status", arguments: ["-s"])
      expect(res).to eq(" M lib/norn.rb")
    end

    it "returns helpful error text on command failure" do
      git_tool = registry.resolve("git")
      
      expect(Open3).to receive(:capture3).with("git", "checkout", "non-existent", chdir: anything).and_return(["", "error: pathspec 'non-existent' did not match any file", double(success?: false)])
      
      res = git_tool.call(subcommand: "checkout", arguments: ["non-existent"])
      expect(res).to include("Error executing git checkout")
      expect(res).to include("error: pathspec 'non-existent'")
    end
  end

  describe "Unified execution & hook integration" do
    let(:git_tool) { registry.resolve("git") }

    it "triggers the :before_subprocess_execute middleware hook" do
      hook_triggered = false
      Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
        hook_triggered = true
        payload
      end

      allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
      git_tool.call(subcommand: "status")
      expect(hook_triggered).to be true
    end

    it "executes rewritten command returned by hook" do
      Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
        Dry::Monads::Success(payload.merge(command: "git diff"))
      end

      expect(Open3).to receive(:capture3).with("git", "diff", chdir: anything).and_return(["diff output", "", double(success?: true)])
      res = git_tool.call(subcommand: "status")
      expect(res).to eq("diff output")
    end

    it "uses Norn::Container['subprocess.shell'] when registered" do
      subshell = double("Subshell")
      expect(subshell).to receive(:execute).with("git status").and_return(
        Norn::Execution::Outcome.new(stdout: "status output", stderr: "", exit_code: 0)
      )
      allow(Norn::Container).to receive(:key?).with("subprocess.shell").and_return(true)
      allow(Norn::Container).to receive(:[]).with("subprocess.shell").and_return(subshell)

      res = git_tool.call(subcommand: "status")
      expect(res).to eq("status output")
    end
  end
end
