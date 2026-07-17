require "spec_helper"

RSpec.describe RSpecPlugin, norn_plugins: :rspec do
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
      expect(described_class.plugin_name).to eq("rspec")
    end

    it "subclasses Norn::Plugin" do
      expect(described_class.ancestors).to include(Norn::Plugin)
    end
  end

  describe "#on_tool_register" do
    it "registers the rspec tool in the global ToolRegistry" do
      rspec_tool = registry.resolve("rspec")

      expect(rspec_tool).not_to be_nil
      expect(rspec_tool.name).to eq("rspec")
      expect(rspec_tool).to be_a(Norn::Plugins::RSpec::RSpecTool)
    end
  end

  describe "Capabilities and Danger Guard Evaluation" do
    let(:tool) do
      Norn::Plugins::RSpec::RSpecTool.new("rspec", "desc", {})
    end

    it "requires sys_execute capability" do
      expect(tool.capabilities_for).to contain_exactly(:sys_execute)
    end

    it "classifies rspec execution as safe/not dangerous" do
      expect(tool.dangerous?).to be false
    end
  end

  describe "Mocked command execution" do
    context "when Gemfile is present" do
      it "runs with bundle exec rspec" do
        rspec_tool = registry.resolve("rspec")
        
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
          if path.end_with?("Gemfile")
            true
          else
            original_method.call(path)
          end
        end

        expect(Open3).to receive(:capture3)
          .with("bundle", "exec", "rspec", chdir: anything)
          .and_return(["Finished in 0.1 seconds\n1 example, 0 failures", "", double(success?: true)])

        res = rspec_tool.call({})
        expect(res).to include("Finished in 0.1 seconds")
      end
    end

    context "when Gemfile is absent" do
      it "runs with rspec directly" do
        rspec_tool = registry.resolve("rspec")
        
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
          if path.end_with?("Gemfile")
            false
          else
            original_method.call(path)
          end
        end

        expect(Open3).to receive(:capture3)
          .with("rspec", chdir: anything)
          .and_return(["Finished in 0.1 seconds\n1 example, 0 failures", "", double(success?: true)])

        res = rspec_tool.call({})
        expect(res).to include("Finished in 0.1 seconds")
      end
    end

    context "with path and line number" do
      it "formats the path argument correctly" do
        rspec_tool = registry.resolve("rspec")
        
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
          if path.end_with?("Gemfile")
            false
          else
            original_method.call(path)
          end
        end

        expect(Open3).to receive(:capture3)
          .with("rspec", "spec/my_spec.rb:42", chdir: anything)
          .and_return(["1 example, 0 failures", "", double(success?: true)])

        res = rspec_tool.call(path: "spec/my_spec.rb", line_number: 42)
        expect(res).to include("1 example, 0 failures")
      end
    end

    context "with additional arguments" do
      it "appends extra arguments to the command" do
        rspec_tool = registry.resolve("rspec")
        
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
          if path.end_with?("Gemfile")
            false
          else
            original_method.call(path)
          end
        end

        expect(Open3).to receive(:capture3)
          .with("rspec", "spec/my_spec.rb", "--format", "documentation", chdir: anything)
          .and_return(["1 example, 0 failures", "", double(success?: true)])

        res = rspec_tool.call(path: "spec/my_spec.rb", arguments: ["--format", "documentation"])
        expect(res).to include("1 example, 0 failures")
      end
    end

    context "on command failure" do
      it "returns failure output" do
        rspec_tool = registry.resolve("rspec")
        
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
          if path.end_with?("Gemfile")
            false
          else
            original_method.call(path)
          end
        end

        expect(Open3).to receive(:capture3)
          .with("rspec", chdir: anything)
          .and_return(["", "Failure/Error: expect(1).to eq(2)", double(success?: false)])

        res = rspec_tool.call({})
        expect(res).to include("RSpec execution failed:")
        expect(res).to include("Failure/Error: expect(1).to eq(2)")
      end
    end
  end

  describe "Unified execution & hook integration" do
    let(:rspec_tool) { registry.resolve("rspec") }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(anything).and_wrap_original do |original_method, path|
        if path.end_with?("Gemfile")
          false
        else
          original_method.call(path)
        end
      end
    end

    it "triggers the :before_subprocess_execute middleware hook" do
      hook_triggered = false
      Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
        hook_triggered = true
        payload
      end

      allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
      rspec_tool.call({})
      expect(hook_triggered).to be true
    end

    it "executes rewritten command returned by hook" do
      Norn::PluginManager.subscribe(:before_subprocess_execute) do |payload|
        Dry::Monads::Success(payload.merge(command: "rspec spec/other_spec.rb"))
      end

      expect(Open3).to receive(:capture3).with("rspec", "spec/other_spec.rb", chdir: anything).and_return(["rspec output", "", double(success?: true)])
      res = rspec_tool.call({})
      expect(res).to eq("rspec output")
    end

    it "uses Norn::Container['subprocess.shell'] when registered" do
      subshell = double("Subshell")
      expect(subshell).to receive(:execute).with("rspec").and_return(
        Norn::Execution::Outcome.new(stdout: "rspec output", stderr: "", exit_code: 0)
      )
      allow(Norn::Container).to receive(:key?).with("subprocess.shell").and_return(true)
      allow(Norn::Container).to receive(:[]).with("subprocess.shell").and_return(subshell)

      res = rspec_tool.call({})
      expect(res).to eq("rspec output")
    end
  end
end
