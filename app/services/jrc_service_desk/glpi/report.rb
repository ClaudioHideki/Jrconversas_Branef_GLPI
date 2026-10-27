# frozen_string_literal: true

class JrcServiceDesk::Glpi::Report
  def self.build(rows)
    count_by = ->(key) { rows.group_by { |row| row[key].presence || 'unclassified' }.transform_values(&:size) }
    deadlines = rows.select { |row| row['solution_deadline'].present? }
    { total: rows.size, by_status: count_by.call('status'), by_priority: count_by.call('priority'), by_entity: count_by.call('entity'),
      by_opening_year: rows.group_by { |row| row['opened_at'].to_s[/\A\d{4}/] || 'unclassified' }.transform_values(&:size),
      solution_sla: { with_deadline: deadlines.size, without_deadline: rows.size - deadlines.size,
                      exceeded: deadlines.count { |row| [1, '1', true].include?(row['solution_exceeded']) } },
      generated_at: Time.current.iso8601, coverage: 'authorized_glpi_records' }
  end
end
