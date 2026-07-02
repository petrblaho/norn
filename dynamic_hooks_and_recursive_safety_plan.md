# Norn Dynamic Hooks, Sequential ROP Middlewares, & Recursive Tool Safety Plan

This document outlines the architectural plan to introduce dynamic, meta-extensible hook registrations, monadic sequential ROP middlewares, and secure recursive tool execution to Norn.

---

## 1. Monadic Sequential Middlewares (The ROP Pipeline)

We standardize Norn's lifecycle hooks and plugin events into two distinct categories:

### A. Notifications (Parallel / Fire-and-Forget)
Informational events that do not mutate state and execute in parallel (e.g., `:after_llm_call`).

### B. Middlewares (Sequential ROP / Kleisli Reduction)
Mutating pipelines where the output of one subscriber becomes the input of the next. The entire chain is wrapped in the `Success/Failure` monad track using a monadic `reduce`:

```ruby
# In lib/norn/plugin_manager.rb
def self.trigger_middleware(event, initial_payload)
  subscribers = @lock.synchronize { @subscribers[event.to_sym].dup }
  
  # Accumulate class-based plugin subscribers
  @active_plugins.each do |plugin|
    subscribers << plugin if plugin.respond_to?(event.to_sym)
  end

  # Compose via monadic reduce on the Success track
  subscribers.reduce(Success(initial_payload)) do |result, subscriber|
    result.bind do |payload|
      begin
        if subscriber.respond_to?(:call)
          # Legacy procedural block
          subscriber.call(payload)
        else
          # Class-based OOP plugin instance method
          subscriber.send(event.to_sym, payload)
        end
      rescue => e
        # If any subscriber crashes, immediately derail to Failure track
        Failure(Norn::FailurePayload.new(e, { event: event, payload: payload }))
      end
    end
  end
end
```

---

## 2. Two-Phase Hook Registration (Meta-Extensibility)

To support external plugins declaring their own custom hooks (which other plugins can then subscribe to), Norn implements a **Two-Phase Bootstrap Lifecycle**:

### Phase 1: Hook Declaration
Plugins declare what new events/hooks they introduce during bootstrapping:
```ruby
Norn::PluginManager.declare_hook(:before_git_commit, desc: "ROP middleware. Mutates the commit payload.")
```

### Phase 2: Dynamic Auto-Wiring Subscriptions
Norn automatically scans all instantiated plugin classes, maps their instance methods against the master list of all declared hooks, and auto-subscribes them as active subscribers, eliminating manual boilerplate code.

---

## 3. Recursive Capability-Guarded Tool Calling

Because Norn passes `self` (the active `Mode` instance) as the `context` parameter to `Tool#call(args, context)`, any tool can recursively invoke other tools safely by executing `context.execute_tool(name, args)`.

Because the recursive call routes directly through Norn's centralized security gatekeeper, it is fully protected by capability checks, pre-flight pruning, and interactive CLI prompts.

### Example: Secure Deletion Confirmation
```ruby
Norn::Tool.new(
  "file_delete",
  "Delete a file.",
  schema,
  required_capabilities: [:sys_write]
) do |args, context|
  if context && context.interactive?
    # Recursively invoke the prompt_user tool securely through the gatekeeper!
    confirm_res = context.execute_tool("prompt_user", {
      type: "confirm",
      question: "Are you sure you want to delete '#{args[:path]}'?"
    })

    # Abort if prompt was blocked or denied
    return confirm_res if confirm_res.failure?

    if confirm_res.value! == "yes"
      File.delete(abs_path)
      Success("Successfully deleted #{args[:path]}.")
    else
      Failure(Norn::FailurePayload.new(Norn::ToolError.new("Deletion aborted by user.")))
    end
  else
    raise "Non-interactive delete blocked."
  end
end
```
