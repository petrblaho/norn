module Norn
  class Tool
    attr_reader :name, :description, :parameters, :block, :required_capabilities, :system_instructions, :dangerous

    def initialize(name, description, parameters, required_capabilities: [:sys_execute], system_instructions: nil, dangerous: false, &block)
      @name = name.to_s
      @description = description
      @parameters = parameters
      @required_capabilities = Array(required_capabilities)
      @system_instructions = system_instructions
      @dangerous = dangerous
      @block = block

      # Enforce strict arity/signature checks on tool registration to fail fast on invalid bindings
      if @block && ![-1, 0, 1, 2].include?(@block.arity)
        raise Norn::Error, "Interface Violation: Tool '#{name}' block must accept either (args) or (args, context) signature."
      end
    end

    def capabilities_for(args = {})
      # Default to baseline static capabilities. 
      # Subclasses or specific tools can override this to inspect arguments dynamically.
      @required_capabilities
    end

    def dangerous?(args = {})
      # Default to baseline static danger classification.
      # Parametric/dynamic tools can override this to inspect arguments dynamically (e.g. true for 'reset --hard', false for 'status').
      @dangerous
    end

    def call(args, context = nil)
      # Ensure arguments are symbolized for easy access
      symbolized_args = symbolize_keys(args)
      
      # Pass both arguments and the execution context (the calling mode instance) to the block
      if @block.arity == 2
        @block.call(symbolized_args, context)
      else
        @block.call(symbolized_args)
      end
    end

    private

    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
      end
    end
  end
end
