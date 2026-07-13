require "stringio"

module Norn
  module RSpec
    class IoSession
      attr_reader :input, :output

      def initialize(initial_inputs = [])
        # We end each input with a newline to simulate pressing enter in gets/readline
        input_data = Array(initial_inputs).map { |inp| inp.end_with?("\n") ? inp : "#{inp}\n" }.join
        @input = StringIO.new(input_data)
        @output = StringIO.new
      end

      # Dynamically write/feed more input (simulating typing in mid-run)
      def send_input(text)
        current_pos = @input.pos
        # Append and recreate StringIO to preserve stream reading pointer
        new_string = @input.string + (text.end_with?("\n") ? text : "#{text}\n")
        @input = StringIO.new(new_string)
        @input.pos = current_pos
      end

      # Reads current printed output, stripping ANSI/terminal control codes and carriage returns by default
      def read_output(strip_ansi: true)
        text = @output.string
        if strip_ansi
          strip_ansi_codes(text).gsub("\r", "")
        else
          text
        end
      end

      private

      def strip_ansi_codes(text)
        text.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")
      end
    end

    module IoHelpers
      # Fluent helper to initialize a mock I/O session
      def norn_io(*initial_inputs)
        IoSession.new(initial_inputs)
      end
    end
  end
end

RSpec::Matchers.define :have_produced do |expected|
  match do |io_session|
    @actual = io_session.read_output
    @actual.include?(expected)
  end

  failure_message do |io_session|
    "expected that the Norn I/O session would have produced:\n" \
    "  #{expected.inspect}\n" \
    "but the actual cleaned output was:\n" \
    "  #{@actual.inspect}"
  end

  failure_message_when_negated do |io_session|
    "expected that the Norn I/O session would NOT have produced:\n" \
    "  #{expected.inspect}\n" \
    "but it did. Cleaned output was:\n" \
    "  #{@actual.inspect}"
  end
end

RSpec::Matchers.define :have_produced_in_order do |*expected_sequence|
  match do |io_session|
    @actual = io_session.read_output
    
    current_index = 0
    expected_sequence.all? do |expected|
      found_pos = @actual.index(expected, current_index)
      if found_pos
        current_index = found_pos + expected.length
        true
      else
        @missing = expected
        false
      end
    end
  end

  failure_message do |io_session|
    if @missing
      "expected that the Norn I/O session would have produced:\n" \
      "  #{@missing.inspect}\n" \
      "following the previous matched sequences, but it was missing.\n" \
      "Entire actual cleaned output was:\n" \
      "  #{@actual.inspect}"
    else
      "expected sequence matching failed."
    end
  end
end

RSpec.configure do |config|
  config.include Norn::RSpec::IoHelpers
end
