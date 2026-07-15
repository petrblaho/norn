module Norn
  module Execution
    class Outcome
      attr_reader :stdout, :stderr, :exit_code

      def initialize(stdout: "", stderr: "", exit_code: 0)
        @stdout = stdout.to_s
        @stderr = stderr.to_s
        @exit_code = exit_code.to_i
      end

      def success?
        @exit_code == 0
      end

      def failure?
        !success?
      end

      def +(other)
        self.class.new(
          stdout: [@stdout, other.stdout].reject(&:empty?).join("\n"),
          stderr: [@stderr, other.stderr].reject(&:empty?).join("\n"),
          exit_code: [self.exit_code, other.exit_code].max
        )
      end

      def to_s
        if success?
          stdout
        else
          "Execution Failed (exit code #{exit_code}):\n#{stderr}\n#{stdout}"
        end
      end
    end
  end
end
