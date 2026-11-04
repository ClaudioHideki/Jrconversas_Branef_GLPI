# frozen_string_literal: true

class JrcServiceDesk::Glpi::Report
  def self.build(rows)
    report = { total: 0, by_status: Hash.new(0), by_priority: Hash.new(0), by_entity: Hash.new(0),
               by_opening_year: Hash.new(0), by_technician: Hash.new(0),
               solution_sla: { with_deadline: 0, without_deadline: 0, exceeded: 0 },
               generated_at: Time.current.iso8601, coverage: 'authorized_glpi_records' }
    rows.each do |row|
      report[:total] += 1
      { status: :by_status, priority: :by_priority, entity: :by_entity, technician: :by_technician }.each do |field, group|
        report[group][row[field.to_s].presence || 'unclassified'] += 1
      end
      report[:by_opening_year][row['opened_at'].to_s[/\A\d{4}/] || 'unclassified'] += 1
      deadline = row['solution_deadline'].present?
      report[:solution_sla][deadline ? :with_deadline : :without_deadline] += 1
      report[:solution_sla][:exceeded] += 1 if deadline && [1, '1', true].include?(row['solution_exceeded'])
    end
    report
  end
end
