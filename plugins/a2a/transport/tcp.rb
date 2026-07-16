require "socket"
require "thread"

module Norn
  module Plugins
    module A2A
      module Transport
        class TCP < Base
          def initialize(host: "127.0.0.1", port: 4567)
            @host = host
            @port = port
            @server = nil
            @client = nil
            @thread = nil
            @lock = Mutex.new
            @running = false
          end

          def start(&block)
            @lock.synchronize do
              return if @running
              @running = true
            end

            @server = TCPServer.new(@host, @port)
            @thread = Thread.new do
              while @running
                begin
                  # Standalone local-loopback proxy pattern: handles single concurrent client safely
                  @client = @server.accept
                  while @running && line = @client.gets
                    # Scrub inputs cleanly
                    sanitized_line = line.force_encoding("UTF-8").scrub.strip
                    block.call(sanitized_line) unless sanitized_line.empty?
                  end
                rescue => e
                  # Connection closed or server stopped
                ensure
                  @client.close if @client && !@client.closed?
                end
              end
            end
          end

          def write(payload)
            @lock.synchronize do
              if @client && !@client.closed?
                begin
                  @client.puts(payload)
                rescue
                  # Ignore pipe write failures
                end
              end
            end
          end

          def stop
            @lock.synchronize do
              return unless @running
              @running = false
            end

            begin
              @client.close if @client && !@client.closed?
              @server.close if @server && !@server.closed?
            rescue
            ensure
              @thread.join if @thread && @thread.alive?
            end
          end
        end
      end
    end
  end
end
