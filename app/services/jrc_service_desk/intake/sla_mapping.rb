# frozen_string_literal: true

class JrcServiceDesk::Intake::SlaMapping
  def initialize(route, expected)
    @route = route
    @expected = expected
  end

  def definitions
    raise ArgumentError, 'intake_sla_conflict' if @route.key?('sla') && @route.key?('slas')
    unless @route.key?('slas')
      return [] if @expected.fetch('unit') == 'none' && @route['sla'].nil?

      return [[@route.fetch('sla'), @expected]]
    end
    raise ArgumentError, 'intake_creation_attributes_required' unless @route['creation_attributes'] == true

    slas = JrcServiceDesk::Input.attributes(@route['slas'], %w[own resolve])
    raise ArgumentError, 'intake_sla_unmapped' if slas.empty? || (@expected['unit'] != 'none' && !slas.key?('resolve'))
    raise ArgumentError, 'intake_sla_unexpected' if @expected['unit'] == 'none' && slas.key?('resolve')

    slas.map do |purpose, value|
      sla = JrcServiceDesk::Input.attributes(value, %w[id purpose calendar_id expected])
      raise ArgumentError, 'intake_sla_unmapped' unless sla['purpose'] == purpose

      JrcServiceDesk::Input.id(sla.fetch('id'))
      JrcServiceDesk::Glpi::Identifiers.remote(sla.fetch('calendar_id'))
      expected = purpose == 'resolve' ? @expected : JrcServiceDesk::Input.attributes(sla.fetch('expected'), %w[duration unit])
      if purpose == 'resolve' && sla.key?('expected') && sla['expected'] != expected
        raise ArgumentError, 'intake_sla_mismatch'
      end
      unless %w[hours days].include?(expected['unit']) && expected['duration'].is_a?(Integer) && expected['duration'].positive?
        raise ArgumentError, 'intake_sla_unmapped'
      end
      [sla, expected]
    end
  end
end
