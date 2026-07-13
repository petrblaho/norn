require "net/http"
require "uri"
require "cgi"

module Norn
  module Plugins
    module WebTools
      class Fetcher
        MAX_REDIRECTS = 5
        TIMEOUT = 10 # seconds

        class << self
          def fetch(url_str)
            begin
              uri = URI.parse(url_str)
              unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
                return "Error: Invalid URL. Only HTTP and HTTPS protocols are supported."
              end
            rescue URI::InvalidURIError => e
              return "Error: Invalid URL syntax - #{e.message}"
            end

            response_or_err = fetch_with_redirects(uri, MAX_REDIRECTS)
            if response_or_err.is_a?(Net::HTTPSuccess)
              clean_html(response_or_err.body)
            elsif response_or_err.is_a?(String)
              response_or_err
            else
              code = response_or_err.respond_to?(:code) ? response_or_err.code : nil
              "Error: Failed to fetch URL (HTTP Status #{code})"
            end
          end

          private

          def fetch_with_redirects(uri, limit)
            return "Error: Too many HTTP redirects." if limit <= 0

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "https")
            http.open_timeout = TIMEOUT
            http.read_timeout = TIMEOUT

            request = Net::HTTP::Get.new(uri.request_uri)
            request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36"

            begin
              response = http.request(request)
            rescue Timeout::Error
              return "Error: Connection timed out after #{TIMEOUT} seconds."
            rescue SocketError
              return "Error: Failed to resolve or connect to host #{uri.host}."
            rescue OpenSSL::SSL::SSLError => e
              return "Error: SSL handshake failed - #{e.message}."
            rescue => e
              return "Error: Network exception - #{e.class} #{e.message}."
            end

            if response.is_a?(Net::HTTPSuccess)
              response
            elsif response.is_a?(Net::HTTPRedirection)
              location = response["location"]
              return "Error: Redirect location header missing." unless location

              begin
                new_uri = URI.join(uri.to_s, location)
              rescue URI::InvalidURIError => e
                return "Error: Invalid redirect URL - #{e.message}"
              end

              fetch_with_redirects(new_uri, limit - 1)
            else
              response
            end
          end

          def clean_html(html)
            return "" unless html

            # 1. Strip <script>, <style>, <head>, <svg> and their contents
            cleaned = html.gsub(/<script\b[^>]*>.*?<\/script>/mi, " ")
            cleaned.gsub!(/<style\b[^>]*>.*?<\/style>/mi, " ")
            cleaned.gsub!(/<head\b[^>]*>.*?<\/head>/mi, " ")
            cleaned.gsub!(/<svg\b[^>]*>.*?<\/svg>/mi, " ")

            # 2. Strip other HTML tags
            cleaned.gsub!(/<[^>]+>/, " ")

            # 3. Unescape HTML entities (CGI.unescapeHTML)
            cleaned = CGI.unescapeHTML(cleaned)

            # 4. Format whitespace and lines
            lines = cleaned.split("\n").map do |line|
              line.gsub(/[ \t]+/, " ").strip
            end

            # Remove empty lines or compact them
            non_empty_lines = lines.reject(&:empty?)

            # Join with single newline
            text = non_empty_lines.join("\n")

            # 5. Limit max characters to keep the LLM response context reasonable
            max_chars = 12000
            if text.length > max_chars
              "#{text[0...max_chars]}\n\n... [Content Truncated to #{max_chars} characters] ..."
            else
              text
            end
          end
        end
      end
    end
  end
end

class WebToolsPlugin < Norn::Plugin
  def self.plugin_name
    "web_tools"
  end

  def on_tool_register(registry)
    registry.register(Norn::Tool.new(
      "web_fetch",
      "Fetches the contents of a URL and returns clean, text-only content (removing HTML tags, scripts, and styles).",
      {
        type: "object",
        properties: {
          url: { type: "string", description: "The absolute HTTP/HTTPS URL to fetch." }
        },
        required: ["url"]
      },
      required_capabilities: [:net_egress]
    ) { |args|
      url = args[:url]
      Norn::Plugins::WebTools::Fetcher.fetch(url)
    })
  end
end
