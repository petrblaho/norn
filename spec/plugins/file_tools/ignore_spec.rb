require "spec_helper"
require "tmpdir"
require_relative "../../../plugins/file_tools/path_helper"

RSpec.describe Norn::Plugins::FileTools::IgnoreFilter do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  context "default excludes" do
    subject(:filter) { described_class.new(tmpdir) }

    it "always ignores .git directory" do
      expect(filter.ignored?(".git/config")).to be true
      expect(filter.ignored?("src/.git/config")).to be true
    end

    it "always ignores node_modules directory" do
      expect(filter.ignored?("node_modules/lodash/index.js")).to be true
      expect(filter.ignored?("src/node_modules/test.js")).to be true
    end

    it "always ignores tmp directory" do
      expect(filter.ignored?("tmp/cache/meta.json")).to be true
    end

    it "does not ignore normal source files" do
      expect(filter.ignored?("lib/norn.rb")).to be false
      expect(filter.ignored?("app/models/user.rb")).to be false
    end
  end

  context "parsing .gitignore patterns" do
    before do
      File.write(File.join(tmpdir, ".gitignore"), <<~GITIGNORE)
        # ignore all log files
        *.log

        # ignore nested cov-report directories
        /cov-report/

        # ignore build outputs specifically in the root dist
        /dist
      GITIGNORE
    end

    subject(:filter) { described_class.new(tmpdir) }

    it "correctly filters extension wildcards" do
      expect(filter.ignored?("development.log")).to be true
      expect(filter.ignored?("log/production.log")).to be true
      expect(filter.ignored?("src/log/debug.log")).to be true
      expect(filter.ignored?("logo.png")).to be false
    end

    it "correctly handles trailing slashes for directory matchers" do
      expect(filter.ignored?("cov-report/index.html")).to be true
      expect(filter.ignored?("cov-report/sub/details.json")).to be true
      expect(filter.ignored?("src/cov-report/nested.html")).to be false
    end

    it "correctly anchors root-level files and folders" do
      expect(filter.ignored?("dist/bundle.js")).to be true
      expect(filter.ignored?("src/dist/bundle.js")).to be false
    end
  end
end
