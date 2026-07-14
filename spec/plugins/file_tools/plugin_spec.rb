require "spec_helper"
require "fileutils"

RSpec.describe "File Tools Plugin", norn_plugins: :file_tools do
  before do
    Norn::ToolRegistry.clear!
    Norn::PluginManager.trigger(:on_tool_register, Norn::ToolRegistry)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  describe "file_write and file_read" do
    it "writes and reads file content relative to workspace root" do
      test_file = "spec/fixtures/temp_test.txt"
      content = "line 1\nline 2\nline 3"

      write_tool = Norn::ToolRegistry.resolve("file_write")
      read_tool = Norn::ToolRegistry.resolve("file_read")

      expect(write_tool).not_to be_nil
      expect(read_tool).not_to be_nil

      # Write
      write_res = write_tool.call(path: test_file, content: content)
      expect(write_res).to include("Successfully wrote")

      # Read full file
      read_res = read_tool.call(path: test_file)
      expect(read_res).to eq("1: line 1\n2: line 2\n3: line 3")

      # Read with offset & limit
      read_slice = read_tool.call(path: test_file, offset: 2, limit: 1)
      expect(read_slice).to eq("2: line 2")

      # Clean up
      FileUtils.rm_f(File.expand_path(test_file, Norn.workspace_root))
    end

    it "prevents directory traversal outside root" do
      read_tool = Norn::ToolRegistry.resolve("file_read")
      expect {
        read_tool.call(path: "../../../etc/passwd")
      }.to raise_error(SecurityError, /Path traversal/)
    end

    it "prevents sibling directory traversal when directory name shares a prefix" do
      read_tool = Norn::ToolRegistry.resolve("file_read")
      sibling_path = File.join(File.dirname(Norn.workspace_root), "#{File.basename(Norn.workspace_root)}_secret/some_file.txt")
      expect {
        read_tool.call(path: sibling_path)
      }.to raise_error(SecurityError, /Path traversal/)
    end
  end

  describe "file_edit" do
    it "replaces unique match in a file" do
      test_file = "spec/fixtures/temp_edit.txt"
      content = "class NornAgent\n  # TODO: implement me\nend"

      write_tool = Norn::ToolRegistry.resolve("file_write")
      edit_tool = Norn::ToolRegistry.resolve("file_edit")
      read_tool = Norn::ToolRegistry.resolve("file_read")

      write_tool.call(path: test_file, content: content)

      # Edit
      edit_res = edit_tool.call(path: test_file, old_string: "# TODO: implement me", new_string: "def self.run; end")
      expect(edit_res).to include("Successfully updated")

      # Read back
      read_res = read_tool.call(path: test_file)
      expect(read_res).to eq("1: class NornAgent\n2:   def self.run; end\n3: end")

      # Clean up
      FileUtils.rm_f(File.expand_path(test_file, Norn.workspace_root))
    end
  end

  describe "glob and grep" do
    it "performs glob pattern searches and regex matches" do
      glob_tool = Norn::ToolRegistry.resolve("glob")
      grep_tool = Norn::ToolRegistry.resolve("grep")

      # Test glob
      glob_res = glob_tool.call(pattern: "lib/norn/config*.rb")
      expect(glob_res).to include("lib/norn/config.rb")
      expect(glob_res).to include("lib/norn/config_loader.rb")

      # Test grep
      grep_res = grep_tool.call(pattern: "class ConfigLoader", include: "lib/**/*.rb")
      expect(grep_res).to include("lib/norn/config_loader.rb:6: class ConfigLoader")
    end
  end
end
