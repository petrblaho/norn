require "spec_helper"

RSpec.describe "Norn I/O RSpec Helpers" do
  describe "#norn_io" do
    it "creates an IoSession with initial inputs" do
      io = norn_io("hello", "world")
      expect(io.input.gets).to eq("hello\n")
      expect(io.input.gets).to eq("world\n")
    end

    it "allows sending dynamic inputs" do
      io = norn_io("first")
      expect(io.input.gets).to eq("first\n")
      
      io.send_input("second")
      expect(io.input.gets).to eq("second\n")
    end

    it "collects printed output" do
      io = norn_io
      io.output.print "Hello "
      io.output.puts "world!"
      
      expect(io.read_output).to eq("Hello world!\n")
    end

    it "strips ANSI colors and carriage returns automatically" do
      io = norn_io
      io.output.print "\e[1;32mGreen\e[0m and \rline-cleared"
      
      expect(io.read_output).to eq("Green and line-cleared")
    end
  end

  describe "Custom Matchers" do
    let(:io) do
      session = norn_io
      session.output.puts "Welcome to Norn!"
      session.output.puts "Thinking..."
      session.output.puts "Norn: Ready."
      session
    end

    describe "have_produced" do
      it "matches partial outputs" do
        expect(io).to have_produced("Welcome to Norn!")
        expect(io).to have_produced("Ready.")
        expect(io).not_to have_produced("Goodbye")
      end
    end

    describe "have_produced_in_order" do
      it "matches ordered sequence" do
        expect(io).to have_produced_in_order("Welcome to Norn!", "Thinking...", "Ready.")
      end

      it "fails if sequence is out of order" do
        expect {
          expect(io).to have_produced_in_order("Ready.", "Thinking...")
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end
    end
  end
end
