require "thread"

module Norn
  class ToolRegistry
    @tools = {}
    @lock = Mutex.new

    class << self
      def register(tool)
        @lock.synchronize do
          @tools[tool.name] = tool
        end
      end

      def resolve(name)
        @lock.synchronize { @tools[name.to_s] }
      end

      def registered_tools
        @lock.synchronize { @tools.values }
      end

      def clear!
        @lock.synchronize do
          @tools.clear
        end
      end
    end
  end
end
