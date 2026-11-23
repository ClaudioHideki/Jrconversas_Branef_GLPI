# frozen_string_literal: true

class JrcServiceDesk::Intake::SlaMapping
  UNITS = %w[hours days].freeze

  def initialize(route, expected)
    @route = route
    @expected = expected
  end

  def definitions
    raise ArgumentError, 'intake_sla_conflict' if @route.key?('sla') && @route.key?('slas')

    return legacy_definitions unless @route.key?('slas')

    raise ArgumentError, 'intake_creation_attributes_required' unless @route['creation_attributes'] == true

    slas = JrcServiceDesk::Input.attributes(@route['slas'], %w[own resolve])
    validate_purposes!(slas)
    slas.map { |purpose, value| definition(purpose, value) }
  end

  private

  def legacy_definitions
    return [] if @expected.fetch('unit') == 'none' && @route['sla'].nil?

    [[@route.fetch('sla'), @expected]]
  end

  def validate_purposes!(slas)
    raise ArgumentError, 'intake_sla_unmapped' if slas.empty? || (@expected['unit'] != 'none' && !slas.key?('resolve'))
    raise ArgumentError, 'intake_sla_unexpected' if @expected['unit'] == 'none' && slas.key?('resolve')
  end

  def definition(purpose, value)
    sla = JrcServiceDesk::Input.attributes(value, %w[id purpose calendar_id expected])
    raise ArgumentError, 'intake_sla_unmapped' unless sla['purpose'] == purpose

    JrcServiceDesk::Input.id(sla.fetch('id'))
    JrcServiceDesk::Glpi::Identifiers.remote(sla.fetch('calendar_id'))
    expected = expected_for(purpose, sla)
    unless UNITS.include?(expected['unit']) && expected['duration'].is_a?(Integer) && expected['duration'].positive?
      raise ArgumentError, 'intake_sla_unmapped'
    end

    [sla, expected]
  end

  def expected_for(purpose, sla)
    return JrcServiceDesk::Input.attributes(sla.fetch('expected'), %w[duration unit]) unless purpose == 'resolve'

    raise ArgumentError, 'intake_sla_mismatch' if sla.key?('expected') && sla['expected'] != @expected

    @expected
  end
end
