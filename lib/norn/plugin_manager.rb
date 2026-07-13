require "thread"
require "dry/monads"

module Norn
  class PluginManager
    extend Dry::Monads[:result]

    @subscribers = Hash.new { |h, k| h[k] = [] }
    @declared_hooks = {}
    @active_plugins = []
    @lock = Mutex.new

    class << self
      attr_accessor :active_plugins

      # Subscribe a block to a specific hook event
      def subscribe(event, &block)
        @lock.synchronize do
          @subscribers[event.to_sym] << block
        end
      end

      # Phase 1: Declare a new lifecycle event or custom hook in the system
      def declare_hook(event, desc:)
        @lock.synchronize do
          @declared_hooks[event.to_sym] = desc
        end
      end

      def declared_hooks
        @declared_hooks
      end

      # Trigger an informational event (parallel/notification only). 
      # Does not mutate state, and does not halt on failure.
      def trigger(event, *args)
        # 1. Call legacy block-based subscribers
        blocks = @lock.synchronize { @subscribers[event.to_sym].dup }
        blocks.each do |block|
          begin
            block.call(*args)
          rescue => e
            warn "Norn Plugin Trigger Warning: #{event} subscriber failed - #{e.message}"
          end
        end

        # Auto-instantiate registered plugins if active_plugins is empty (crucial for spec environments)
        if @active_plugins.empty? && Norn::Plugin.registered_plugins.any?
          @active_plugins = Norn::Plugin.registered_plugins.map(&:new)
        end

        # 2. Call matching instance methods on registered OO plugin instances
        @active_plugins.each do |plugin|
          if plugin.respond_to?(event.to_sym)
            begin
              plugin.send(event.to_sym, *args)
            rescue => e
              warn "Norn Plugin Trigger Warning: #{event} on #{plugin.class} failed - #{e.message}"
            end
          end
        end
      end

      # Trigger a sequential ROP middleware pipeline. 
      # Sequentially reduces a Hash payload. If any subscriber fails or returns a Failure,
      # the pipeline checks its recovery policy. If the policy is :recover, Norn logs
      # a non-fatal warning and recovers the previous success payload, otherwise it derails.
      def trigger_middleware(event, initial_payload)
        # 1. Accumulate all subscribers (legacy blocks + OO plugin instances)
        subscribers = @lock.synchronize { @subscribers[event.to_sym].dup }

        # Auto-instantiate registered plugins if active_plugins is empty (crucial for spec environments)
        if @active_plugins.empty? && Norn::Plugin.registered_plugins.any?
          @active_plugins = Norn::Plugin.registered_plugins.map(&:new)
        end

        @active_plugins.each do |plugin|
          subscribers << plugin if plugin.respond_to?(event.to_sym)
        end

        # 2. Sequentially reduce payload using monadic composition (Kleisli reduce)
        subscribers.reduce(Success(initial_payload)) do |result, subscriber|
          result.bind do |payload|
            policy = resolve_policy(subscriber, event)

            begin
              output = if subscriber.respond_to?(:call)
                         subscriber.call(payload)
                       else
                         subscriber.send(event.to_sym, payload)
                       end

              # Standardize returned output to a monadic Result
              if output.is_a?(Dry::Monads::Result)
                if output.failure? && policy == :recover
                  # Non-fatal Failure: Report and recover previous success payload!
                  report_non_fatal_failure(output.failure, event, subscriber)
                  Success(payload)
                else
                  output
                end
              elsif output.is_a?(Hash)
                Success(output)
              else
                # If the subscriber returned nil/nothing, preserve input payload unchanged
                Success(payload)
              end
            rescue => e
              # Catch subscriber exceptions and handle according to policy
              failure = Norn::FailurePayload.new(e, { event: event, payload: payload })

              if policy == :recover
                # Non-fatal Exception: Report and recover previous success payload!
                report_non_fatal_failure(failure, event, subscriber)
                Success(payload)
              else
                # Fatal Exception: Derail immediately to Failure track
                Failure(failure)
              end
            end
          end
        end
      end

      # Reset all subscribers, hooks, and active plugins (useful for testing)
      def reset!
        @lock.synchronize do
          @subscribers.clear
          @declared_hooks.clear
          @active_plugins.clear
        end
      end

      # Auto-wire declared standard Norn core hooks
      def register_core_hooks!
        declare_hook :on_boot, desc: "Fires when Norn finishes loading dependencies."
        declare_hook :on_tool_register, desc: "Fires to populate the global ToolRegistry."
        declare_hook :on_cli_register, desc: "Fires to let plugins register custom CLI commands."
        declare_hook :on_mode_register, desc: "Fires to register custom execution modes."
        declare_hook :on_user_input, desc: "ROP middleware. Intercepts and processes raw user input before execution."
        declare_hook :before_llm_call, desc: "Fires before calling LLM. Allows inspecting/mutating messages."
        declare_hook :after_llm_call, desc: "Fires after LLM call completes. Informational."
        declare_hook :on_render_response, desc: "ROP middleware. Formats/renders response text in-place."
        declare_hook :after_tool_call, desc: "Fires after a tool execution completes. Informational."
        declare_hook :after_llm_response, desc: "Fires when an LLM response with metadata is received. Informational."
      end

      private

      # Resolves the execution policy (:fatal or :recover) for a subscriber on an event
      def resolve_policy(subscriber, event)
        if subscriber.class.respond_to?(:hook_policies)
          subscriber.class.hook_policies[event.to_sym] || :fatal
        else
          :fatal
        end
      end

      # Prints a non-intrusive warning to stderr for non-fatal failures
      def report_non_fatal_failure(failure, event, subscriber)
        name = subscriber.class.respond_to?(:plugin_name) ? subscriber.class.plugin_name : subscriber.class.name
        warn "\e[90m[Norn Warning] Optional hook '#{event}' in '#{name}' failed: #{failure.message} (Skipped, continuing safely...)\e[0m"
      end
    end
  end
end

# Auto-initialize core hooks on load
Norn::PluginManager.register_core_hooks!
