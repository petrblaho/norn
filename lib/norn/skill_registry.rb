require "thread"

module Norn
  class SkillRegistry
    @skills = {}
    @lock = Mutex.new
    @fallback_active_skills = []

    class << self
      def register(skill)
        @lock.synchronize do
          @skills[skill.name.to_s.downcase] = skill
        end
      end

      def resolve(name)
        @lock.synchronize do
          @skills[name.to_s.downcase]
        end
      end

      def registered_skills
        @lock.synchronize do
          @skills.values
        end
      end

      def clear!
        @lock.synchronize do
          @skills.clear
          @fallback_active_skills.clear
        end
        # Reset session storage if available
        begin
          session = Norn["session"]
          session.set(:active_skills, []) if session
        rescue
        end
      end

      # Retrieves currently activated Norn::Skill objects in this session
      def active_skills
        session = nil
        begin
          session = Norn["session"]
        rescue
        end

        if session
          names = session.get(:active_skills) || []
          names.map { |n| resolve(n) }.compact
        else
          @fallback_active_skills
        end
      end

      # Mark a skill as activated
      def activate!(name)
        skill = resolve(name)
        return false unless skill

        session = nil
        begin
          session = Norn["session"]
        rescue
        end

        if session
          names = session.get(:active_skills) || []
          unless names.include?(skill.name)
            session.set(:active_skills, names + [skill.name])
          end
        else
          @fallback_active_skills ||= []
          unless @fallback_active_skills.include?(skill)
            @fallback_active_skills << skill
          end
        end
        true
      end

      # Scans text and activates any matching skills based on their triggers (case-insensitive)
      def check_and_activate!(text)
        activated_any = false
        registered_skills.each do |skill|
          if skill.matches?(text)
            activated_any = true if activate!(skill.name)
          end
        end
        activated_any
      end

      # Generates XML catalog for Tier 1 Progressive Disclosure
      def generate_catalog_xml
        return "" if registered_skills.empty?

        xml = []
        xml << "<available_skills>"
        registered_skills.each do |skill|
          xml << "  <skill>"
          xml << "    <name>#{skill.name}</name>"
          xml << "    <description>#{skill.description}</description>"
          xml << "    <location>#{skill.location}</location>" if skill.location
          xml << "  </skill>"
        end
        xml << "</available_skills>"
        xml.join("\n")
      end
    end
  end
end
