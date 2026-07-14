require "thread"

module Norn
  class Session
    def initialize
      @lock = Mutex.new
      clear!
    end

    def get(key)
      @lock.synchronize { @store[key.to_sym] }
    end

    def set(key, value)
      @lock.synchronize { @store[key.to_sym] = value }
    end

    def increment(key, by = 1)
      @lock.synchronize do
        k = key.to_sym
        @store[k] = (@store[k] || 0) + by
      end
    end

    def append(key, item)
      @lock.synchronize do
        k = key.to_sym
        @store[k] ||= []
        @store[k] << item
      end
    end

    def record_tokens(prompt:, completion:, provider: nil, model: nil)
      @lock.synchronize do
        @store[:prompt_tokens] += prompt
        @store[:completion_tokens] += completion
        @store[:total_tokens] += (prompt + completion)

        if provider && model
          @store[:provider_usage] ||= {}
          @store[:provider_usage][provider.to_sym] ||= {}
          @store[:provider_usage][provider.to_sym][model.to_sym] ||= { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
          
          usage = @store[:provider_usage][provider.to_sym][model.to_sym]
          usage[:prompt_tokens] += prompt
          usage[:completion_tokens] += completion
          usage[:total_tokens] += (prompt + completion)
        end
      end
    end

    def record_tool_call(tool_name:, arguments:, result: nil, error: nil)
      append(:tool_calls, {
        tool: tool_name,
        arguments: arguments,
        result: result,
        error: error,
        timestamp: Time.now
      })
    end

    def record_message(role:, content:, **extra)
      append(:history, {
        role: role,
        content: content,
        timestamp: Time.now
      }.merge(extra))
    end

    def to_h
      @lock.synchronize { deep_dup(@store) }
    end

    def stats
      to_h
    end

    def clear!
      @lock.synchronize do
        @store = {
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          provider_usage: {},
          tool_calls: [],
          history: [],
          metadata: {}
        }
      end
    end

    private

    def deep_dup(object)
      case object
      when Hash
        object.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array
        object.map { |v| deep_dup(v) }
      when String
        object.dup.force_encoding("UTF-8").scrub
      when Symbol, Numeric, TrueClass, FalseClass, NilClass
        object
      else
        object.respond_to?(:dup) ? object.dup : object
      end
    end
  end
end
