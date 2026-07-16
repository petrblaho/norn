require "spec_helper"
require "socket"
require_relative "../../../plugins/a2a/transport/base"
require_relative "../../../plugins/a2a/transport/tcp"

RSpec.describe Norn::Plugins::A2A::Transport::TCP do
  let(:port) { 4999 } # Ephemeral test port
  subject(:transport) { described_class.new(port: port) }

  after do
    transport.stop
  end

  it "binds to localhost and receives newline-delimited lines" do
    received_lines = []
    
    transport.start do |line|
      received_lines << line
    end

    # Connect client
    client = TCPSocket.new("127.0.0.1", port)
    client.puts("test_line_1")
    client.puts("test_line_2")
    client.close

    # Wait briefly for background thread to read
    sleep 0.1

    expect(received_lines).to eq(["test_line_1", "test_line_2"])
  end

  it "supports thread-safe writing back to the client connection" do
    transport.start do |line|
      # Echo back
      transport.write("echo: #{line}")
    end

    client = TCPSocket.new("127.0.0.1", port)
    client.puts("hello")
    response = client.gets
    client.close

    expect(response.strip).to eq("echo: hello")
  end
end
