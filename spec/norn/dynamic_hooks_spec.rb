require "spec_helper"
require "norn/plugin_manager"
require "norn/plugin"
require "norn/errors"
require "dry/monads"

RSpec.describe "Dynamic Hooks and Monadic ROP Middlewares" do
  include Dry::Monads[:result]

  before do
    Norn::PluginManager.reset!
    Norn::Plugin.clear!
    Norn::PluginManager.register_core_hooks!
  end

  after do
    Norn::PluginManager.reset!
    Norn::Plugin.clear!
    Norn::PluginManager.register_core_hooks!
  end

  describe "Hook Declarations" do
    it "automatically registers core standard hooks on load" do
      expect(Norn::PluginManager.declared_hooks.keys).to include(
        :on_boot, :on_tool_register, :on_cli_register, 
        :on_mode_register, :before_llm_call, :after_llm_call, :on_render_response
      )
    end

    it "allows custom plugins to declare new hooks dynamically" do
      Norn::PluginManager.declare_hook(:before_git_commit, desc: "Fires before commits")
      expect(Norn::PluginManager.declared_hooks.keys).to include(:before_git_commit)
    end
  end

  describe "Monadic ROP Middleware reduction pipeline" do
    it "runs sequential subscribers on the Success track, passing mutated outputs as next inputs" do
      # Register custom mutating hook
      Norn::PluginManager.declare_hook(:mutate_message, desc: "ROP middleware")

      # Subscriber 1: appends ' hello'
      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        payload[:text] += " hello"
        payload
      end

      # Subscriber 2: appends ' world'
      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        payload[:text] += " world"
        payload
      end

      result = Norn::PluginManager.trigger_middleware(:mutate_message, { text: "norn" })

      expect(result).to be_success
      expect(result.value![:text]).to eq("norn hello world")
    end

    it "handles subscribers returning explicit Success monads cleanly" do
      Norn::PluginManager.declare_hook(:mutate_message, desc: "ROP middleware")

      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        payload[:text] += " success"
        Success(payload)
      end

      result = Norn::PluginManager.trigger_middleware(:mutate_message, { text: "norn" })

      expect(result).to be_success
      expect(result.value![:text]).to eq("norn success")
    end

    it "instantly halts the pipeline and derails to Failure if any subscriber returns a Failure monad under :fatal policy" do
      Norn::PluginManager.declare_hook(:mutate_message, desc: "ROP middleware")

      called_sub_3 = false

      # Subscriber 1: success
      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        payload[:text] += " first"
        Success(payload)
      end

      # Subscriber 2: fails
      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        Failure(Norn::FailurePayload.new("Validation failed!"))
      end

      # Subscriber 3: should never be executed
      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        called_sub_3 = true
        payload
      end

      result = Norn::PluginManager.trigger_middleware(:mutate_message, { text: "norn" })

      expect(result).to be_failure
      expect(result.failure.message).to eq("Validation failed!")
      expect(called_sub_3).to be(false)
    end

    it "instantly halts the pipeline and derails to Failure if any subscriber raises an exception under :fatal policy" do
      Norn::PluginManager.declare_hook(:mutate_message, desc: "ROP middleware")

      Norn::PluginManager.subscribe(:mutate_message) do |payload|
        raise "Crashed!"
      end

      result = Norn::PluginManager.trigger_middleware(:mutate_message, { text: "norn" })

      expect(result).to be_failure
      expect(result.failure.message).to eq("Crashed!")
    end

    it "recovers from a Failure monad if the subscriber has the :recover policy, logging a warning and passing previous payload" do
      Norn::PluginManager.declare_hook(:mutate_message, desc: "ROP middleware")

      allow(Norn::PluginManager).to receive(:warn)

      # Subclassing plugin with :recover policy
      recoverable_plugin_class = Class.new(Norn::Plugin) do
        def self.plugin_name; "test_recoverable"; end
        def self.hook_policies; { mutate_message: :recover }; end
        def mutate_message(payload)
          Dry::Monads::Failure(Norn::FailurePayload.new("Recoverable error"))
        end
      end

      allow(Norn::Plugin).to receive(:registered_plugins).and_return([recoverable_plugin_class])

      result = Norn::PluginManager.trigger_middleware(:mutate_message, { text: "norn" })

      expect(result).to be_success
      expect(result.value![:text]).to eq("norn") # Previous payload intact!
    end

    it "recovers and passes payload forward if a :recover policy subscriber raises an exception" do
      Norn::PluginManager.declare_hook(:mutate_message, desc: "ROP middleware")

      allow(Norn::PluginManager).to receive(:warn)

      recoverable_plugin_class = Class.new(Norn::Plugin) do
        def self.plugin_name; "test_recoverable"; end
        def self.hook_policies; { mutate_message: :recover }; end
        def mutate_message(payload)
          raise "Crashed recoverable exception"
        end
      end

      allow(Norn::Plugin).to receive(:registered_plugins).and_return([recoverable_plugin_class])

      result = Norn::PluginManager.trigger_middleware(:mutate_message, { text: "norn" })

      expect(result).to be_success
      expect(result.value![:text]).to eq("norn") # Previous payload intact!
    end
  end
end
