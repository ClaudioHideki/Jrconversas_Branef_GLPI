# frozen_string_literal: true

require 'cgi'

module JrcServiceDesk::Glpi::Normalize
  FIELDS = { '2' => 'id', '1' => 'title', '80' => 'entity', '12' => 'status', '3' => 'priority', '15' => 'opened_at', '14' => 'type',
             '19' => 'updated_at', '17' => 'solved_at', '16' => 'closed_at', '7' => 'category', '5' => 'technician',
             '8' => 'group', '18' => 'solution_deadline', '82' => 'solution_exceeded', '155' => 'response_deadline',
             '30' => 'solution_sla', '37' => 'response_sla' }.freeze

  def self.text(value)
    ActionView::Base.full_sanitizer.sanitize(CGI.unescapeHTML(value.to_s))
  end

  def self.search(row)
    FIELDS.to_h { |key, name| [name, row[key].is_a?(String) ? text(row[key]) : row[key]] }.merge('source' => 'glpi')
  end

  def self.detail(row)
    row.slice('id', 'entities_id', 'status', 'priority', 'type', 'urgency', 'impact', 'date', 'date_mod', 'solvedate', 'closedate',
              'time_to_resolve', 'time_to_own', 'itilcategories_id', 'slas_id_ttr', 'slas_id_tto').merge(
      'title' => text(row['name']), 'description' => text(row['content']),
      'description_html' => JrcServiceDesk::Glpi::Content.rich(row['content'], from_source: true), 'source' => 'glpi'
    )
  end
end
