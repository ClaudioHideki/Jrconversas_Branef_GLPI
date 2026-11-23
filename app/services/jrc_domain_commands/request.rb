require 'time'

class JrcDomainCommands::Request
  COMMANDS = %w[create_lead create_task create_meeting].freeze
  INTAKE_COMMANDS = %w[service_desk_intake service_desk_status service_desk_handoff].freeze
  PROTOCOL = 'jrc-domain-commands/1'.freeze

  def self.available?
    JrcFlowEffects::ControlRevision.available? && JrcFlowEffectReceipt.column_names.include?('domain_result')
  end

  def self.parse(raw)
    value = decode(raw)
    raise ArgumentError, 'domain_command' unless value.is_a?(Hash) && (COMMANDS + INTAKE_COMMANDS).include?(value['command'])
    return validate_intake(value) if INTAKE_COMMANDS.include?(value['command'])

    keys = value['command'] == 'create_lead' ? ['command'] : %w[command title due_at owner_id]
    raise ArgumentError, 'domain_keys' unless value.keys.sort == keys.sort

    validate_activity(value) unless value['command'] == 'create_lead'
    value
  end

  def self.validate_intake(value)
    validate_intake_keys(value)
    valid_episode = value['episode_key'].is_a?(String) && JrcServiceDesk::Intake::Submission::UUID.match?(value['episode_key'])
    raise ArgumentError, 'intake_episode' unless valid_episode
    return value if value['command'] == 'service_desk_status'

    validate_intake_fields(value)
    validate_handoff(value) if value['command'] == 'service_desk_handoff'
    value
  end

  def self.validate_intake_keys(value)
    expected = %w[command episode_key]
    expected += %w[configuration_id configuration_revision phase input] unless value['command'] == 'service_desk_status'
    expected << 'target' if value['command'] == 'service_desk_handoff'
    expected << 'capture_error' if value['command'] == 'service_desk_handoff' && value.key?('capture_error')
    raise ArgumentError, 'domain_keys' unless value.keys.sort == expected.sort
  end

  def self.validate_handoff(value)
    raise ArgumentError, 'intake_phase' unless value['phase'] == 'handoff'
    if value.key?('capture_error') && %w[intake_capture_too_large intake_capture_invalid].exclude?(value['capture_error'])
      raise ArgumentError, 'intake_capture_error'
    end

    validate_handoff_target(value.fetch('target'))
  end

  def self.validate_handoff_target(input)
    target = JrcServiceDesk::Input.attributes(input, %w[team_id agent_id])
    valid = target.keys.sort == %w[agent_id team_id] && target.values.count(nil) == 1 && target.values.compact.all? { |id| valid_owner?(id) }
    raise ArgumentError, 'intake_handoff_target' unless valid
  end

  def self.validate_intake_fields(value)
    %w[configuration_id configuration_revision].each do |key|
      raise ArgumentError, 'intake_configuration' unless valid_owner?(value[key])
    end
    raise ArgumentError, 'intake_phase' unless %w[qualified handoff].include?(value['phase'])
    raise ArgumentError, 'intake_input' unless value['input'].is_a?(Hash) &&
                                               (value['input'].keys - JrcServiceDesk::Intake::Input::FIELDS).empty?
  end

  def self.decode(raw)
    raise ArgumentError, 'domain_payload' unless raw.is_a?(String) && raw.bytesize <= 8192

    JSON.parse(raw, max_nesting: 8)
  rescue JSON::ParserError
    raise ArgumentError, 'domain_payload'
  end

  def self.validate_activity(value)
    valid = valid_title?(value['title']) && valid_owner?(value['owner_id']) &&
            value['due_at'].is_a?(String) && value['due_at'].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/)
    raise ArgumentError, 'domain_activity' unless valid

    Time.iso8601(value.fetch('due_at'))
  end

  def self.valid_title?(title)
    title.is_a?(String) && title.strip.present? && title.bytesize <= 200
  end

  def self.valid_owner?(owner)
    owner.is_a?(Integer) && owner.between?(1, JrcFlowEffects::Request::MAX_SAFE_INTEGER)
  end
end
