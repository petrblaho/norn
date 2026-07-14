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

    def session_approval_label(args = {})
      "Approve '#{name}' for the rest of this session"
    end

    def session_approval_pattern(args = {})
      { tool_name: name }
    end

    def session_approved?(session, args)
      return false if session.nil?
      
      approvals = session.get(:session_approvals) || []
      has_approval = approvals.any? { |app| app[:tool_name] == name }
      
      has_approval && (!dangerous?(args) || allow_session_danger?)
    end

    def allow_session_danger?
      @dangerous
    end

    def call(args, context = nil)
      # Ensure arguments are symbolized for easy access
      symbolized_args = symbolize_keys(args)
      
      # Pass both arguments and the execution context (the calling mode instance) to the block
      result = if @block.arity == 2
        @block.call(symbolized_args, context)
      else
        @block.call(symbolized_args)
      end

      sanitize_output(result)
    end

    private

    def sanitize_output(object)
      case object
      when String
        object.dup.force_encoding("UTF-8").scrub
      when Hash
        object.each_with_object({}) { |(k, v), h| h[k] = sanitize_output(v) }
      when Array
        object.map { |v| sanitize_output(v) }
      else
        object
      end
    end

    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
      end
    end
  end
end
