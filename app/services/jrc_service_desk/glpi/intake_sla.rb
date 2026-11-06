# frozen_string_literal: true

# Preserve the document's unit. A native SLA and its SLM must confirm duration/calendar/purpose.
class JrcServiceDesk::Glpi::IntakeSla
  def validate!(access:, client:, entity_id:, mapping:, expected:)
    values = JrcServiceDesk::Input.attributes(mapping, %w[id purpose calendar_id])
    raise ArgumentError unless %w[resolve own].include?(values['purpose'])

    id = JrcServiceDesk::Input.id(values.fetch('id'))
    calendar = JrcServiceDesk::Glpi::Identifiers.remote(values.fetch('calendar_id'))
    sla = client.get("SLA/#{id}")
    slm_id = JrcServiceDesk::Input.id(sla.fetch('slms_id'))
    slm = client.get("SLM/#{slm_id}")
    access.unit_for(entity_id)
    valid = identity_matches?(sla, slm, id, slm_id, entity_id) && definition_matches?(sla, values, expected) &&
            calendar_matches?(slm, calendar)
    raise JrcServiceDesk::Glpi::Error.new('intake_sla_mismatch', 422) unless valid

    validate_calendar!(access, client, calendar)
    true
  end

  private

  def identity_matches?(sla, slm, id, slm_id, entity)
    sla['id'].to_s == id.to_s && slm['id'].to_s == slm_id.to_s &&
      sla['entities_id'].to_s == entity.to_s && slm['entities_id'].to_s == entity.to_s &&
      [1, '1', true].exclude?(sla['is_deleted']) && [1, '1', true].exclude?(slm['is_deleted'])
  end

  def definition_matches?(sla, values, expected)
    sla['type'].to_s == (values['purpose'] == 'resolve' ? '0' : '1') &&
      sla['number_time'].to_s == expected.fetch('duration').to_s &&
      sla['definition_time'] == { 'hours' => 'hour', 'days' => 'day' }.fetch(expected.fetch('unit'))
  end

  def calendar_matches?(slm, calendar)
    slm['calendars_id'].to_s == calendar.to_s && [0, '0', false].include?(slm['use_ticket_calendar'])
  end

  def validate_calendar!(access, client, calendar)
    return unless calendar.positive?

    JrcServiceDesk::Glpi::ResourceQuery.new.raw(access: access, client: client, kind: 'calendars', id: calendar)
  end
end
