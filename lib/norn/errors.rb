module Norn
  class Error < StandardError
    attr_reader :context

    def initialize(message = nil, context: {})
      super(message)
      @context = context
    end
  end

  class UsageError < Error; end
  class ConfigurationError < Error; end
  class ProviderError < Error; end
  class ToolError < Error; end

  class FailurePayload
    attr_reader :error, :context

    def initialize(error, context = {})
      @error = case error
               when String
                 Norn::Error.new(error)
               when Exception
                 error
               else
                 Norn::Error.new(error.to_s)
               end

      # 1. Early scan the error message to discover and cache keys in memory
      Norn::SecretScrubber.scrub(@error.message)

      # 2. Sanitize context with all cached keys loaded
      @context = sanitize_context(context || {})
    end

    def with_context(additional_context)
      self.class.new(@error, @context.merge(additional_context || {}))
    end

    def message
      scrub(@error.message)
    end

    def backtrace
      @error.backtrace
    end

    private

    def sanitize_context(obj)
      case obj
      when String
        scrub(obj)
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          h[k] = sanitize_context(v)
        end
      when Array
        obj.map { |v| sanitize_context(v) }
      when Exception
        # Convert raw exceptions to sanitized string representation to prevent leakage on inspection
        scrub(obj.inspect)
      else
        obj
      end
    end

    def scrub(text)
      Norn::SecretScrubber.scrub(text)
    end
  end
end
