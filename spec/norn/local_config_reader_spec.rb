require "spec_helper"
require "norn/local_config_reader"

RSpec.describe Norn::LocalConfigReader do
  let(:temp_root) { File.expand_path("../fixtures", __dir__) }

  before do
    FileUtils.mkdir_p(temp_root)
  end

  after do
    # Cleanup temp files
    FileUtils.rm_f(File.join(temp_root, ".norn.yml"))
    FileUtils.rm_f(File.join(temp_root, ".norn.yaml"))
    FileUtils.rm_f(File.join(temp_root, ".norn.json"))
  end

  it "locates and parses YAML config files correctly" do
    yaml_content = "openai_model: 'custom-gpt-4o'\ntemperature: 0.8\n"
    File.write(File.join(temp_root, ".norn.yml"), yaml_content)

    reader = described_class.new(temp_root)
    config = reader.read

    expect(config).to eq({
      openai_model: "custom-gpt-4o",
      temperature: 0.8
    })
  end

  it "locates and parses JSON config files correctly" do
    json_content = '{"gemini_model": "custom-gemini-3.5", "temperature": 0.5}'
    File.write(File.join(temp_root, ".norn.json"), json_content)

    reader = described_class.new(temp_root)
    config = reader.read

    expect(config).to eq({
      gemini_model: "custom-gemini-3.5",
      temperature: 0.5
    })
  end

  it "returns an empty hash if no local config files are found" do
    reader = described_class.new(temp_root)
    expect(reader.read).to eq({})
  end

  describe "when executed from outside the repository root" do
    it "defaults root_path to Dir.pwd" do
      reader = described_class.new
      expect(reader.root_path).to eq(Dir.pwd)
    end

    it "loads configuration from the current working directory" do
      require "tmpdir"
      original_pwd = Dir.pwd
      Dir.mktmpdir do |dir|
        # Resolve any symlinks in the temporary directory to match Dir.pwd's behavior
        real_dir = File.realdirpath(dir)
        Dir.chdir(real_dir) do
          yaml_content = "openai_model: 'external-gpt-4o'\ntemperature: 0.7\n"
          File.write(".norn.yml", yaml_content)

          reader = described_class.new
          expect(reader.root_path).to eq(real_dir)
          expect(reader.read).to eq({
            openai_model: "external-gpt-4o",
            temperature: 0.7
          })
        end
      end
    end
  end
end
