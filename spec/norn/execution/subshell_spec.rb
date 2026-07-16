require "spec_helper"
require "norn/execution/subshell"
require "norn/execution/outcome"

RSpec.describe Norn::Execution::Subshell do
  subject(:subshell) { described_class.new }

  after do
    subshell.stop if subshell.started?
  end

  it "lazily starts the background process" do
    expect(subshell.started?).to be false
    subshell.start
    expect(subshell.started?).to be true
  end

  it "preserves directory changes across consecutive commands" do
    subshell.start
    subshell.execute("cd lib")
    outcome = subshell.execute("pwd")
    expect(outcome.stdout).to include("lib")
  end

  it "retains exported environment variables" do
    subshell.start
    subshell.execute("export NORN_TEST_ENV=jester")
    outcome = subshell.execute("echo $NORN_TEST_ENV")
    expect(outcome.stdout.strip).to eq("jester")
  end

  it "streams stdout chunks in real-time without leaking the sentinel boundary" do
    subshell.start
    chunks = []
    outcome = subshell.execute("echo 'hello world'") do |type, chunk|
      chunks << chunk if type == :stdout
    end
    
    streamed_text = chunks.join
    expect(streamed_text).to include("hello world")
    expect(streamed_text).not_to include("NORN_OUT")
    expect(outcome.stdout).to include("hello world")
    expect(outcome.stdout).not_to include("NORN_OUT")
  end

  it "handles commands that consume standard input without deadlocking" do
    subshell.start
    # 'cat' normally reads stdin indefinitely. Stdin isolation must redirect it.
    outcome = subshell.execute("cat")
    expect(outcome.exit_code).to eq(0)
  end
end
