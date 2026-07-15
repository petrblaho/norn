require "spec_helper"
require "open3"

RSpec.describe "bin/norn executable" do
  let(:bin_path) { File.expand_path("../../bin/norn", __dir__) }

  it "boots correctly and displays help output showing the chat command" do
    # Run the executable and capture stdout, stderr, and exit status
    stdout, stderr, status = Open3.capture3("bundle exec #{bin_path}")

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("Commands:")
    expect(stderr).to include("norn chat")
    expect(stderr).to include("Start an interactive chat session with Norn")
  end
end
