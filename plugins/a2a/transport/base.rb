module Norn
  module Plugins
    module A2A
      module Transport
        class Base
          def start(&block)
            raise NotImplementedError, "Subclasses must implement #start"
          end

          def write(payload)
            raise NotImplementedError, "Subclasses must implement #write"
          end

          def stop
            raise NotImplementedError, "Subclasses must implement #stop"
          end
        end
      end
    end
  end
end
