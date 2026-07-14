require "spec_helper"
require "fileutils"

RSpec.describe "Skills System" do
  let(:temp_dir) { File.expand_path("../../tmp/skills_test", __dir__) }

  before do
    FileUtils.mkdir_p(temp_dir)
    Norn::SkillRegistry.clear!
  end

  after do
    FileUtils.rm_rf(temp_dir)
    Norn::SkillRegistry.clear!
  end

  describe Norn::Skill do
    let(:valid_md) do
      <<~MARKDOWN
        ---
        name: test-skill
        description: A fine test skill.
        triggers:
          - testtrigger
          - /test
        invocable: true
        argument-hint: "[action]"
        ---
        # Test Skill Instructions
        This is the body of the skill.
      MARKDOWN
    end

    let(:malformed_md) do
      <<~MARKDOWN
        ---
        name: malformed-skill
        description: This description: has an unquoted colon: which normally breaks YAML.
        triggers:
          - malformed
        invocable: false
        ---
        Body content.
      MARKDOWN
    end

    let(:missing_name_md) do
      <<~MARKDOWN
        ---
        description: A skill missing an explicit name.
        ---
        Instructions body.
      MARKDOWN
    end

    it "parses a valid skill markdown string successfully" do
      skill = Norn::Skill.parse_content(valid_md)
      expect(skill).not_to be_nil
      expect(skill.name).to eq("test-skill")
      expect(skill.description).to eq("A fine test skill.")
      expect(skill.triggers).to eq(["testtrigger", "/test"])
      expect(skill.invocable).to be(true)
      expect(skill.argument_hint).to eq("[action]")
      expect(skill.instructions).to eq("# Test Skill Instructions\nThis is the body of the skill.")
    end

    it "handles malformed YAML with unquoted colons gracefully" do
      skill = Norn::Skill.parse_content(malformed_md)
      expect(skill).not_to be_nil
      expect(skill.name).to eq("malformed-skill")
      expect(skill.description).to eq("This description: has an unquoted colon: which normally breaks YAML.")
      expect(skill.invocable).to be(false)
      expect(skill.instructions).to eq("Body content.")
    end

    it "falls back to parent directory name if name is missing but filepath is provided" do
      skill = Norn::Skill.parse_content(missing_name_md, "/path/to/my-fallback-skill/SKILL.md")
      expect(skill).not_to be_nil
      expect(skill.name).to eq("my-fallback-skill")
      expect(skill.description).to eq("A skill missing an explicit name.")
    end

    it "triggers matches? properly and case-insensitively" do
      skill = Norn::Skill.parse_content(valid_md)
      expect(skill.matches?("I want to run a testtrigger today")).to be(true)
      expect(skill.matches?("Using /TEST now")).to be(true)
      expect(skill.matches?("random string")).to be(false)
    end
  end

  describe Norn::SkillRegistry do
    let(:skill_a) do
      Norn::Skill.new(
        name: "skill-a",
        description: "Skill A desc.",
        triggers: ["trigger_a"],
        invocable: false,
        argument_hint: nil,
        instructions: "Instructions A",
        location: "/some/path/SKILL.md"
      )
    end

    let(:skill_b) do
      Norn::Skill.new(
        name: "skill-b",
        description: "Skill B desc.",
        triggers: ["trigger_b"],
        invocable: true,
        argument_hint: "[args]",
        instructions: "Instructions B",
        location: "/other/path/SKILL.md"
      )
    end

    before do
      Norn::SkillRegistry.register(skill_a)
      Norn::SkillRegistry.register(skill_b)
    end

    it "resolves and lists registered skills" do
      expect(Norn::SkillRegistry.resolve("skill-a")).to eq(skill_a)
      expect(Norn::SkillRegistry.resolve("SKILL-B")).to eq(skill_b)
      expect(Norn::SkillRegistry.registered_skills).to contain_exactly(skill_a, skill_b)
    end

    it "tracks and deduplicates active skills" do
      expect(Norn::SkillRegistry.active_skills).to be_empty
      
      # Activate
      Norn::SkillRegistry.activate!("skill-a")
      expect(Norn::SkillRegistry.active_skills).to contain_exactly(skill_a)

      # Deduplicate
      Norn::SkillRegistry.activate!("skill-a")
      expect(Norn::SkillRegistry.active_skills).to contain_exactly(skill_a)
    end

    it "pre-emptively activates skills matching user text triggers" do
      activated = Norn::SkillRegistry.check_and_activate!("Hey we need trigger_b here!")
      expect(activated).to be(true)
      expect(Norn::SkillRegistry.active_skills).to contain_exactly(skill_b)
    end

    it "generates XML catalog representation correctly" do
      xml = Norn::SkillRegistry.generate_catalog_xml
      expect(xml).to include("<available_skills>")
      expect(xml).to include("<name>skill-a</name>")
      expect(xml).to include("<description>Skill A desc.</description>")
      expect(xml).to include("<location>/some/path/SKILL.md</location>")
    end
  end

  describe Norn::SkillLoader do
    before do
      # Mock home directory and workspace root to point to our test temp_dir
      allow(Norn).to receive(:workspace_root).and_return(temp_dir)
      allow(Dir).to receive(:home).and_return(File.join(temp_dir, "home"))
    end

    it "loads skills across project and home folders and overrides with precedence warnings" do
      # Create home skills
      home_skills = File.join(temp_dir, "home", ".agents", "skills")
      home_skill_dir = File.join(home_skills, "common-skill")
      FileUtils.mkdir_p(home_skill_dir)
      File.write(File.join(home_skill_dir, "SKILL.md"), <<~YAML)
        ---
        name: common-skill
        description: Home level common skill.
        triggers: ["common"]
        ---
        Home body
      YAML

      # Create project skills overriding home skill
      project_skills = File.join(temp_dir, ".agents", "skills")
      project_skill_dir = File.join(project_skills, "common-skill")
      FileUtils.mkdir_p(project_skill_dir)
      File.write(File.join(project_skill_dir, "SKILL.md"), <<~YAML)
        ---
        name: common-skill
        description: Project level common skill.
        triggers: ["common"]
        ---
        Project body
      YAML

      # Also create a project-specific skill
      project_only_dir = File.join(project_skills, "project-skill")
      FileUtils.mkdir_p(project_only_dir)
      File.write(File.join(project_only_dir, "SKILL.md"), <<~YAML)
        ---
        name: project-skill
        description: Project unique skill.
        triggers: ["unique"]
        ---
        Unique body
      YAML

      # Expect a warning when shadowing occurs
      expect {
        Norn::SkillLoader.load_all
      }.to output(/shadowing\/overriding/).to_stderr

      # Verify final registry state (Project-level won!)
      resolved = Norn::SkillRegistry.resolve("common-skill")
      expect(resolved.description).to eq("Project level common skill.")
      expect(resolved.instructions).to eq("Project body")

      expect(Norn::SkillRegistry.resolve("project-skill")).not_to be_nil
    end
  end

  describe "SkillsPlugin Integration", norn_plugins: :skills do
    let(:skill) do
      Norn::Skill.new(
        name: "testskill",
        description: "Interactive Test Skill",
        triggers: ["interactive_test"],
        invocable: true,
        argument_hint: "[action]",
        instructions: "Test Instructions",
        location: File.join(temp_dir, "SKILL.md")
      )
    end

    before do
      Norn::SkillRegistry.clear!
      Norn::SkillRegistry.register(skill)
      
      # Populate registry via hook
      Norn::ToolRegistry.clear!
      Norn::PluginManager.trigger(:on_tool_register, Norn::ToolRegistry)
    end

    after do
      Norn::ToolRegistry.clear!
    end

    it "registers the activate_skill tool" do
      tool = Norn::ToolRegistry.resolve("activate_skill")
      expect(tool).not_to be_nil
      expect(tool.required_capabilities).to eq([:sys_read])
    end

    it "synthesizes invocable dynamic tools" do
      tool = Norn::ToolRegistry.resolve("testskill")
      expect(tool).not_to be_nil
      expect(tool.required_capabilities).to eq([:sys_execute])
      expect(tool.dangerous?).to be(true)
    end

    it "activates a skill and returns formatted XML instructions via activate_skill tool" do
      tool = Norn::ToolRegistry.resolve("activate_skill")
      res = tool.call(name: "testskill")
      
      expect(res).to include("<activated_skill name=\"testskill\">")
      expect(res).to include("<instructions>")
      expect(res).to include("Test Instructions")
      expect(res).to include("</instructions>")
      expect(Norn::SkillRegistry.active_skills).to contain_exactly(skill)
    end

    it "automatically activates a skill when triggered in user input middleware" do
      payload = { text: "We need some interactive_test here", action: :continue }
      result = Norn::PluginManager.trigger_middleware(:on_user_input, payload)
      
      expect(result.success?).to be(true)
      expect(Norn::SkillRegistry.active_skills).to contain_exactly(skill)
    end

    it "renders `/skills` list without crashing even if a skill description contains a percent sign" do
      percent_skill = Norn::Skill.new(
        name: "percent-skill",
        description: "Skill with 100% discount",
        triggers: ["percent_trigger"],
        invocable: false,
        argument_hint: nil,
        instructions: "Percent Instructions",
        location: "/some/path/SKILL.md"
      )
      Norn::SkillRegistry.register(percent_skill)

      mock_registry = double("Registry")
      handler_block = nil
      expect(mock_registry).to receive(:register).with("/skills", any_args) do |trigger, desc, &block|
        handler_block = block
      end
      allow(mock_registry).to receive(:register).with(start_with("/"), any_args)

      plugin = Norn::Plugins::Skills::SkillsPlugin.new
      plugin.on_slash_commands_register(mock_registry)

      expect(handler_block).not_to be_nil
      payload = { text: "/skills list" }
      res = handler_block.call(payload)
      expect(res).to be_success
      expect(res.value![:output]).to include("percent-skill")
      expect(res.value![:output]).to include("100% discount")
    end
  end
end
