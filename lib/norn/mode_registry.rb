require "thread"

module Norn
  class ModeRegistry
    @modes = {}
    @descriptions = {}
    @lock = Mutex.new

    class << self
      def register(name, mode_class, description: "")
        # Enforce subclassing contract
        unless mode_class < Norn::Mode
          raise Norn::Error, "Registration Failure: Mode '#{name}' (#{mode_class}) must inherit from Norn::Mode"
        end

        # Enforce abstract method contract
        missing_methods = Norn::Mode::ABSTRACT_METHODS.reject do |method|
          mode_class.instance_methods.include?(method) && 
            mode_class.instance_method(method).owner != Norn::Mode
        end

        unless missing_methods.empty?
          raise Norn::Error, "Interface Violation: Mode class #{mode_class} must implement abstract methods: #{missing_methods.join(', ')}"
        end

        @lock.synchronize do
          @modes[name.to_s] = mode_class
          @descriptions[name.to_s] = description
        end
      end

      def resolve(name)
        @lock.synchronize { @modes[name.to_s] }
      end

      def registered_modes
        @lock.synchronize { @modes.keys }
      end

      def description_for(name)
        @lock.synchronize { @descriptions[name.to_s] }
      end

      def clear!
        @lock.synchronize do
          @modes.clear
          @descriptions.clear
        end
      end
    end
  end
end
