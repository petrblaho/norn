require "open3"

module Norn
  module Plugins
    module Rtk
      class RtkPlugin < Norn::Plugin
        def self.plugin_name
          "rtk"
        end

        def initialize
          @rtk_available = check_rtk_available
          if !@rtk_available && Norn.config.rtk_enabled && Norn.config.rtk_warn_if_missing
            warn "[rtk] rtk binary not found in PATH — plugin disabled"
          end
        end

        def respond_to_missing?(method, include_private = false)
          if method.to_sym == :before_subprocess_execute
            @rtk_available && Norn.config.rtk_enabled
          else
            super
          end
        end

        def respond_to?(method, include_private = false)
          if method.to_sym == :before_subprocess_execute
            !!(@rtk_available && Norn.config.rtk_enabled)
          else
            super
          end
        end

        def before_subprocess_execute(payload)
          return payload unless @rtk_available && Norn.config.rtk_enabled

          command = payload[:command]
          return payload if command.nil? || command.to_s.strip.empty?

          rtk_bin = Norn.config.rtk_path || "rtk"

          begin
            stdout, stderr, status = Open3.capture3(rtk_bin, "rewrite", command.to_s)
            if status.success?
              rewritten = stdout.strip
              if !rewritten.empty? && rewritten != command
                payload = payload.merge(command: rewritten)
              end
            end
          rescue => e
            # Pass through unchanged
          end

          payload
        end

        private

        def check_rtk_available
          custom_path = Norn.config.rtk_path
          if custom_path
            return File.file?(custom_path) && File.executable?(custom_path)
          end

          exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
          ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |path|
            exts.each do |ext|
              exe = File.join(path, "rtk#{ext}")
              return true if File.file?(exe) && File.executable?(exe)
            end
          end
          false
        end
      end
    end
  end
end
