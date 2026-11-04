# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'active_support'
require 'uri'
require 'action_view'
require 'cgi'

module JrcServiceDesk
  module Glpi; end
end
content_file = File.expand_path('../../app/services/jrc_service_desk/glpi/content.rb', __dir__)
require content_file if File.file?(content_file)
require_relative '../../app/services/jrc_service_desk/glpi/normalize'

class GlpiContentTest < Minitest::Test
  def test_detail_exposes_safe_rich_source_content_alongside_searchable_text
    payload = JrcServiceDesk::Glpi::Normalize.detail('id' => 1, 'content' => CGI.escapeHTML('<table><tr><td>Cell</td></tr></table><script>bad()</script>'))
    assert_includes payload['description_html'].to_s, '<table>'
    refute_includes payload['description_html'].to_s, '<script'
    refute_includes payload['description'], '<table>'
  end
  def test_rich_tables_and_safe_references_survive_without_active_content
    assert defined?(JrcServiceDesk::Glpi::Content), 'Missing the GLPI content sanitizer'
    html = '<table style="color:red"><tr><td colspan="2" onclick="alert(1)">Cell</td></tr></table>' \
           '<a href="https://example.invalid/reference" title="Reference">Link</a>' \
           '<a href="javascript:alert(1)">Unsafe</a><img src="https://example.invalid/tracker">'
    result = JrcServiceDesk::Glpi::Content.rich(html)
    assert_includes result, '<table>'
    assert_includes result, 'colspan="2"'
    assert_includes result, 'href="https://example.invalid/reference"'
    refute_match(/onclick|style=|javascript:|<img/i, result)
  end

  def test_glpi_transport_entities_are_decoded_once_before_rich_sanitization
    assert defined?(JrcServiceDesk::Glpi::Content), 'Missing the GLPI content sanitizer'
    encoded = CGI.escapeHTML('<p>Reference</p><script>alert(1)</script><a href="javascript:alert(1)">Bad</a>')
    result = JrcServiceDesk::Glpi::Content.rich(encoded, from_source: true)
    assert_includes result, '<p>Reference</p>'
    refute_match(/<script|javascript:/i, result)
    literal = JrcServiceDesk::Glpi::Content.rich('&amp;lt;p&amp;gt;Literal&amp;lt;/p&amp;gt;', from_source: true)
    refute_includes literal, '<p>Literal</p>'
  end

  def test_plain_text_keeps_literal_markup_and_is_the_default_contract
    assert defined?(JrcServiceDesk::Glpi::Content), 'Missing the GLPI content sanitizer'
    assert_equal '&lt;table&gt;Literal&lt;/table&gt;<br>Next', JrcServiceDesk::Glpi::Content.plain("<table>Literal</table>\nNext")
  end
end
