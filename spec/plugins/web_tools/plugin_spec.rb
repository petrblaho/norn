require "spec_helper"
require "net/http"

RSpec.describe "Web Tools Plugin", norn_plugins: :web_tools do
  before do
    Norn::ToolRegistry.clear!
    Norn::PluginManager.trigger(:on_tool_register, Norn::ToolRegistry)
  end

  after do
    Norn::ToolRegistry.clear!
  end

  describe "Plugin registration" do
    it "registers the web_fetch tool" do
      web_fetch = Norn::ToolRegistry.resolve("web_fetch")
      expect(web_fetch).not_to be_nil
      expect(web_fetch.name).to eq("web_fetch")
      expect(web_fetch.required_capabilities).to contain_exactly(:net_egress)
    end
  end

  describe "web_fetch execution" do
    let(:web_fetch) { Norn::ToolRegistry.resolve("web_fetch") }

    context "when input URL is invalid" do
      it "returns a validation error for non-HTTP/HTTPS schemes" do
        res = web_fetch.call(url: "ftp://example.com")
        expect(res).to include("Error: Invalid URL. Only HTTP and HTTPS protocols are supported.")
      end

      it "returns a validation error for malformed URIs" do
        res = web_fetch.call(url: "::not-a-valid-url::")
        expect(res).to include("Error: Invalid URL syntax")
      end
    end

    context "when HTTP request is successful" do
      it "fetches and cleans HTML content correctly" do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess, body: <<~HTML)
          <html>
            <head>
              <title>Test Page</title>
              <style>body { color: red; }</style>
            </head>
            <body>
              <script>console.log('hello');</script>
              <h1>Hello World!</h1>
              <p>This is a paragraph with <a href="#">a link</a>.</p>
              <svg><path d="M10 10" /></svg>
              <div>And &lt;some&gt; &amp; escaped entities.</div>
            </body>
          </html>
        HTML
        allow(mock_response).to receive(:is_a?) { |klass| klass == Net::HTTPSuccess }

        allow(Net::HTTP).to receive(:new).with("example.com", 80).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=).with(false)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_response)

        res = web_fetch.call(url: "http://example.com/test")

        expect(res).not_to include("<head>")
        expect(res).not_to include("console.log")
        expect(res).not_to include("color: red")
        expect(res).not_to include("path d=")
        expect(res).to include("Hello World!")
        expect(res).to include("This is a paragraph with a link .")
        expect(res).to include("And <some> & escaped entities.")
      end

      it "truncates output if it is excessively long" do
        long_text = "A" * 13000
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess, body: "<html><body>#{long_text}</body></html>")
        allow(mock_response).to receive(:is_a?) { |klass| klass == Net::HTTPSuccess }

        allow(Net::HTTP).to receive(:new).with("example.com", 443).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=).with(true)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_response)

        res = web_fetch.call(url: "https://example.com")
        expect(res.length).to be < 13000
        expect(res).to include("Content Truncated to 12000 characters")
      end
    end

    context "when HTTP request encounters redirects" do
      it "follows redirects and returns the body of the final page" do
        mock_http1 = instance_double(Net::HTTP)
        mock_http2 = instance_double(Net::HTTP)

        mock_redirect = instance_double(Net::HTTPRedirection)
        allow(mock_redirect).to receive(:is_a?) { |klass| klass == Net::HTTPRedirection }
        allow(mock_redirect).to receive(:[]).with("location").and_return("https://example.com/target")

        mock_success = instance_double(Net::HTTPSuccess, body: "<html><body>Target Content</body></html>")
        allow(mock_success).to receive(:is_a?) { |klass| klass == Net::HTTPSuccess }

        allow(Net::HTTP).to receive(:new).with("example.com", 80).and_return(mock_http1)
        allow(mock_http1).to receive(:use_ssl=).with(false)
        allow(mock_http1).to receive(:open_timeout=)
        allow(mock_http1).to receive(:read_timeout=)
        allow(mock_http1).to receive(:request).and_return(mock_redirect)

        allow(Net::HTTP).to receive(:new).with("example.com", 443).and_return(mock_http2)
        allow(mock_http2).to receive(:use_ssl=).with(true)
        allow(mock_http2).to receive(:open_timeout=)
        allow(mock_http2).to receive(:read_timeout=)
        allow(mock_http2).to receive(:request).and_return(mock_success)

        res = web_fetch.call(url: "http://example.com/source")
        expect(res).to eq("Target Content")
      end

      it "limits redirects to prevent infinite loops" do
        mock_http = instance_double(Net::HTTP)
        mock_redirect = instance_double(Net::HTTPRedirection)
        allow(mock_redirect).to receive(:is_a?) { |klass| klass == Net::HTTPRedirection }
        allow(mock_redirect).to receive(:[]).with("location").and_return("http://example.com/loop")

        allow(Net::HTTP).to receive(:new).with("example.com", 80).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=).with(false)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_redirect)

        res = web_fetch.call(url: "http://example.com/loop")
        expect(res).to include("Error: Too many HTTP redirects.")
      end
    end

    context "when network errors occur" do
      it "handles Connection Timeout gracefully" do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_raise(Timeout::Error)

        res = web_fetch.call(url: "http://example.com")
        expect(res).to include("Error: Connection timed out")
      end

      it "handles DNS/SocketError resolution failures" do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_raise(SocketError)

        res = web_fetch.call(url: "http://example.com")
        expect(res).to include("Error: Failed to resolve or connect to host")
      end

      it "handles SSL handshake failure" do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_raise(OpenSSL::SSL::SSLError.new("SSL connection failed"))

        res = web_fetch.call(url: "https://example.com")
        expect(res).to include("Error: SSL handshake failed")
      end
    end
  end
end
