require "spec_helper"
require_relative "../../../plugins/tty_markdown/plugin"
require "tty-markdown"
require "dry/monads"

RSpec.describe "TTY Markdown Plugin" do
  include Dry::Monads[:result]

  before do
    @orig_plugins = Norn::Plugin.registered_plugins.dup
    Norn::PluginManager.reset!
    Norn::Plugin.clear!
    Norn::PluginManager.register_core_hooks!
    # Load the plugin
    load File.expand_path("plugins/tty_markdown/plugin.rb", Dir.pwd)
    # Ensure TTYMarkdownPlugin is in registered_plugins
    unless Norn::Plugin.registered_plugins.include?(TTYMarkdownPlugin)
      Norn::Plugin.registered_plugins << TTYMarkdownPlugin
    end
  end

  after do
    Norn::PluginManager.reset!
    Norn::Plugin.clear!
    @orig_plugins.each { |p| Norn::Plugin.registered_plugins << p }
    Norn::PluginManager.register_core_hooks!
  end

  it "renders markdown into ANSI-colored terminal text on the :on_render_response middleware hook" do
    raw_markdown = "# Heading\n- item 1\n- item 2"
    
    # Trigger the hook using our monadic middleware pipeline
    result = Norn::PluginManager.trigger_middleware(:on_render_response, { text: raw_markdown })

    expect(result).to be_success
    rendered_text = result.value![:text]
    expect(rendered_text).not_to eq(raw_markdown)
    expect(rendered_text).to include("•")
  end

  it "derails the ROP pipeline if an error is raised during parsing under :fatal policy, or logs warning and recovers under :recover policy" do
    allow(TTY::Markdown).to receive(:parse).and_raise(StandardError.new("Parsing error"))

    raw_markdown = "# Heading"
    allow(Norn::PluginManager).to receive(:warn) # suppress console warnings in tests

    result = Norn::PluginManager.trigger_middleware(:on_render_response, { text: raw_markdown })

    # Because TTYMarkdownPlugin defines its policy as :recover, it logs a warning and RECOVERS successfully
    expect(result).to be_success
    expect(result.value![:text]).to eq(raw_markdown) # passes previous raw text unchanged!
  end
end
