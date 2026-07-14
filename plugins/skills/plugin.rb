require "open3"
require "shellwords"

module Norn
  module Plugins
    module Skills
      class SkillsPlugin < Norn::Plugin
        def self.plugin_name
          "skills"
        end

        def on_boot(container)
          # Bootstrapping: Discover and load all skills across all scopes
          Norn::SkillLoader.load_all
        end

        def on_tool_register(registry)
          # 1. Register the activate_skill tool
          activate_tool = Norn::Tool.new(
            "activate_skill",
            "Activate an available skill by name to load its complete, detailed instructions and list bundled resources.",
            {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  description: "The name of the skill to activate (e.g. 'basecamp')."
                }
              },
              required: ["name"]
            },
            required_capabilities: [:sys_read],
            system_instructions: "Use this tool to activate any available skill when the user asks about that domain."
          ) do |args, context|
            name = args[:name].to_s.strip
            skill = Norn::SkillRegistry.resolve(name)
            if skill
              Norn::SkillRegistry.activate!(skill.name)
              
              res = skill.resources
              res_xml = if res.any?
                          res.map { |f| "    <file>#{f}</file>" }.join("\n")
                        else
                          "    <!-- No supporting resources -->"
                        end

              <<~XML
              <activated_skill name="#{skill.name}">
                <instructions>
                  #{skill.instructions}
                </instructions>
                <resources>
              #{res_xml}
                </resources>
              </activated_skill>
              XML
            else
              "Error: Skill '#{name}' not found."
            end
          end

          registry.register(activate_tool)

          # 2. Register a synthesized dynamic tool for every invocable skill
          Norn::SkillRegistry.registered_skills.each do |skill|
            next unless skill.invocable

            synthesized_tool = Norn::Tool.new(
              skill.name,
              skill.description,
              {
                type: "object",
                properties: {
                  arguments: {
                    type: "string",
                    description: "The command line arguments to pass to the #{skill.name} CLI (e.g. '#{skill.argument_hint || 'projects list'}')."
                  }
                },
                required: ["arguments"]
              },
              required_capabilities: [:sys_execute],
              system_instructions: "This tool executes commands for the #{skill.name} CLI. Always activate the skill first if you need to understand how to format your arguments.",
              dangerous: true
            ) do |args, context|
              cmd_name = skill.name
              args_str = args[:arguments].to_s.strip
              args_array = Shellwords.split(args_str)
              full_cmd = [cmd_name] + args_array

              begin
                stdout, stderr, status = Open3.capture3(*full_cmd, chdir: Norn.workspace_root)
                if status.success?
                  stdout
                else
                  "Command execution failed with status #{status.exitstatus}:\n#{stderr}\n#{stdout}"
                end
              rescue => e
                "Failed to execute command: #{e.message}"
              end
            end

            registry.register(synthesized_tool)
          end
        end

        def on_slash_commands_register(registry)
          # Register general /skills command
          registry.register("/skills", "Manage skills (list, activate)") do |payload|
            args = payload[:text].to_s.strip.split(/\s+/)
            subcmd = args[1]&.downcase

            if subcmd == "activate"
              name = args[2]
              if name.nil? || name.empty?
                Dry::Monads::Success(payload.merge(action: :skip, output: "\e[1;31mUsage: /skills activate <name>\e[0m"))
              else
                skill = Norn::SkillRegistry.resolve(name)
                if skill
                  Norn::SkillRegistry.activate!(skill.name)
                  Dry::Monads::Success(payload.merge(action: :skip, output: "\e[1;32mSkill '#{skill.name}' activated.\e[0m"))
                else
                  Dry::Monads::Success(payload.merge(action: :skip, output: "\e[1;31mSkill '#{name}' not found.\e[0m"))
                end
              end
            else
              skills = Norn::SkillRegistry.registered_skills
              if skills.empty?
                output = "\e[1;36mNo skills discovered.\e[0m"
              else
                output = "\e[1;36mDiscovered Skills:\e[0m\n"
                active_names = Norn::SkillRegistry.active_skills.map(&:name)
                skills.each do |skill|
                  status = active_names.include?(skill.name) ? "\e[1;32m[ACTIVE]\e[0m" : "\e[2;37m[INACTIVE]\e[0m"
                  invocable = skill.invocable ? " \e[1;33m[INVOCABLE]\e[0m" : ""
                  output << "  #{status} \e[1;32m%-15s\e[0m - #{skill.description}#{invocable}\n" % skill.name
                end
              end
              Dry::Monads::Success(payload.merge(action: :skip, output: output))
            end
          end

          # For every invocable skill, register a direct slash command
          Norn::SkillRegistry.registered_skills.each do |skill|
            next unless skill.invocable

            registry.register("/#{skill.name}", "Run direct command for #{skill.name} skill") do |payload|
              raw_text = payload[:text].to_s.strip
              cmd_pattern = /^\/#{skill.name}\s*(.*)$/i
              match = raw_text.match(cmd_pattern)
              sub_args_str = match ? match[1].strip : ""

              # Automatically activate the skill in the session if invoked by user
              Norn::SkillRegistry.activate!(skill.name)

              if sub_args_str.empty? && skill.argument_hint
                Dry::Monads::Success(payload.merge(action: :skip, output: "\e[1;31mUsage: /#{skill.name} #{skill.argument_hint}\e[0m"))
              else
                args_array = Shellwords.split(sub_args_str)
                full_cmd = [skill.name] + args_array

                begin
                  stdout, stderr, status = Open3.capture3(*full_cmd, chdir: Norn.workspace_root)
                  output = if status.success?
                             stdout
                           else
                             "\e[1;31mExecution failed with status #{status.exitstatus}:\e[0m\n#{stderr}\n#{stdout}"
                           end
                  Dry::Monads::Success(payload.merge(action: :skip, output: output))
                rescue => e
                  Dry::Monads::Success(payload.merge(action: :skip, output: "\e[1;31mFailed to execute /#{skill.name}: #{e.message}\e[0m"))
                end
              end
            end
          end
        end

        # Hook: pre-emptive trigger-based skill activation
        def on_user_input(payload)
          text = payload[:text].to_s
          Norn::SkillRegistry.check_and_activate!(text)
          Dry::Monads::Success(payload)
        end
      end
    end
  end
end
