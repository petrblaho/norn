require "set"

module Norn
  module SecretScrubber
    @registered_secrets = Set.new

    def self.register_secret(secret)
      return if secret.nil? || secret.strip.empty? || secret.length < 5
      @registered_secrets << secret.strip
    end

    def self.registered_secrets
      # Automatically discover and register environment keys on demand
      ["GEMINI_API_KEY", "OPENAI_API_KEY"].each do |var|
        val = ENV[var]
        register_secret(val) if val
      end

      @registered_secrets.to_a
    end

    def self.scrub(text)
      return text unless text.is_a?(String)

      scrubbed = text.dup

      # 1. Scavenge / discover keys from input text and cache them in memory
      scrubbed.scan(/(?:key=)["']?([^&\s"'`\r\n>#]+)/i) do |match|
        register_secret(match[0])
      end

      scrubbed.scan(/(sk-[a-zA-Z0-9_\-\.]{24,})/i) do |match|
        register_secret(match[0])
      end

      # 2. General-purpose pattern redactors
      scrubbed.gsub!(/(key=)[^&\s"'\r\n]+/i, '\1[REDACTED]')
      scrubbed.gsub!(/sk-[a-zA-Z0-9_\-\.]{24,}/i, 'sk-...[REDACTED]')
      scrubbed.gsub!(/(bearer\s+)[a-zA-Z0-9_\-\.]+/i, '\1[REDACTED]')
      scrubbed.gsub!(/("key"|:key|\bkey\b)\s*(=>|:)\s*["']([^"'\s]+)["']/i, '\1 \2 "[REDACTED]"')

      # 3. Memory lookup: Redact exact matches of all registered secrets
      registered_secrets.each do |secret|
        scrubbed.gsub!(secret, "[REDACTED]")
      end

      scrubbed
    end
  end
end
