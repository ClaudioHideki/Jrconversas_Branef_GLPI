# frozen_string_literal: true

require 'cgi'

# A source description is never trusted HTML and its URLs never receive connector credentials.
module JrcServiceDesk::Glpi::Content
  TAGS = %w[table thead tbody tr th td p br div span strong em u s ul ol li blockquote pre code h1 h2 h3 a].freeze
  ATTRIBUTES = %w[href title colspan rowspan].freeze

  module_function

  def rich(value, from_source: false)
    html = from_source ? CGI.unescapeHTML(value.to_s) : value.to_s
    ActionView::Base.safe_list_sanitizer.sanitize(html, tags: TAGS, attributes: ATTRIBUTES).to_s
  end

  def plain(value)
    CGI.escapeHTML(value.to_s).gsub("\n", '<br>')
  end
end
