class A2APlugin < Norn::Plugin
  def self.plugin_name
    "a2a"
  end

  def on_boot(container)
    require_relative "transport/base"
    require_relative "transport/tcp"
    require_relative "server"

    # Default A2A port 4567, allow override via ENV
    port = (ENV["NORN_A2A_PORT"] || 4567).to_i

    # Initialize TCP transport and A2A broker
    @transport = Norn::Plugins::A2A::Transport::TCP.new(port: port)
    @server = Norn::Plugins::A2A::Server.new(transport: @transport)

    # Start A2A server on background thread to keep standalone session non-blocked
    @transport.start do |line|
      @server.handle_message(line)
    end
  end

  # Cleanup port allocation on Norn exit
  def on_shutdown
    @transport.stop if @transport
  end
end
