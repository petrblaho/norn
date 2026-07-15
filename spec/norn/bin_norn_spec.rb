require "spec_helper"
require "open3"

RSpec.describe "bin/norn executable" do
  let(:bin_path) { File.expand_path("../../bin/norn", __dir__) }

  it "boots correctly and displays help output showing the chat command" do
    # Run the executable and capture stdout, stderr, and exit status
    stdout, stderr, status = Open3.capture3(bin_path)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("Commands:")
    expect(stderr).to include("norn chat")
    expect(stderr).to include("Start an interactive chat session with Norn")
  end

  it "silences git stderr warnings when booting outside of a git repository" do
    require "tmpdir"
    require "fileutils"

    Dir.mktmpdir do |temp_dir|
      # Copy minimum required boot assets to the temp directory
      FileUtils.cp_r(File.expand_path("../../bin", __dir__), temp_dir)
      FileUtils.cp_r(File.expand_path("../../lib", __dir__), temp_dir)
      FileUtils.cp_r(File.expand_path("../../plugins", __dir__), temp_dir)
      FileUtils.cp(File.expand_path("../../Gemfile", __dir__), temp_dir)
      FileUtils.cp(File.expand_path("../../Gemfile.lock", __dir__), temp_dir)
      FileUtils.cp(File.expand_path("../../norn.gemspec", __dir__), temp_dir)

      # Run the executable inside the temp directory (which lacks any parent .git)
      temp_bin_path = File.join(temp_dir, "bin", "norn")
      
      _stdout, stderr, _status = Bundler.with_unbundled_env do
        Open3.capture3(temp_bin_path)
      end

      # Assert that git complains are completely silenced
      expect(stderr).not_to include("fatal: not a git repository")
      expect(stderr).not_to include("Stopping at filesystem boundary")
    end
  end
end
