module Norn
  class ErrorRenderer
    def self.render(failure, debug: ENV["NORN_DEBUG"] == "true" || ENV["DEBUG"] == "true")
      payload = if failure.is_a?(Norn::FailurePayload)
                  failure
                else
                  Norn::FailurePayload.new(failure)
                end

      if debug
        warn "\n🔧 Norn Failure Detected"
        warn "--------------------------------------------------"
        warn "Error:    #{payload.message} (#{payload.error.class})"
        warn "\nContext:"
        if payload.context.any?
          payload.context.each do |k, v|
            # Format keys nicely (e.g., :llm_provider -> "Llm provider")
            formatted_key = k.to_s.split('_').map(&:capitalize).join(' ')
            warn "  • #{formatted_key}: #{scrub(v.inspect)}"
          end
        else
          warn "  • No context captured."
        end
        if payload.backtrace
          warn "\nBacktrace:"
          payload.backtrace.first(15).each { |line| warn "  #{scrub(line)}" }
        end
        warn "--------------------------------------------------\n"
      else
        warn "\e[31mError:\e[0m #{payload.message}"
        if payload.context[:provider]
          warn "Active Provider: #{payload.context[:provider]}"
        end
      end
    end

    def self.scrub(text)
      Norn::SecretScrubber.scrub(text)
    end
  end
end
