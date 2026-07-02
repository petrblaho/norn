module Norn
  module Plugins
    module GitCommitMessage
      # Addon plugin to enrich git commit messages with active LLM context
      class GitCommitMessagePlugin < Norn::Plugin
        def self.plugin_name
          "git_commit_message"
        end

        def before_git_commit(payload)
          return payload unless Norn.config.git_addon_enabled

          provider = Norn.config.llm_provider
          model = if provider == "openai"
                    Norn.config.openai_model || "gpt-4o-mini"
                  elsif provider == "gemini"
                    Norn.config.gemini_model || "gemini-3.5-flash"
                  else
                    "unknown-model"
                  end

          template = Norn.config.git_addon_message || "Created with the use of LLM via Norn"
          addon_msg = template.gsub("LLM", model).gsub("<model>", model)

          arguments = Array(payload[:arguments]).dup
          arguments += ["-m", addon_msg]

          payload.merge(arguments: arguments)
        end
      end
    end
  end
end
