# frozen_string_literal: true

class JrcServiceDesk::Intake::Mapping
  SELECTORS = %w[system location reason subject profile severity].freeze
  attr_reader :route, :requester_id, :destination, :input

  def initialize(demand)
    @input = demand.normalized_input
    mappings = demand.intake_configuration.mappings
    @route = resolve_route(mappings)
    @requester_id = resolve_requester(mappings, demand.contact_id) if route['requester_policy'] == 'mapped_contact'
    @destination = demand.source_context.slice('connection_id', 'connection_version').merge('entity_id' => route['entity_id'])
  end

  def resolve_route(mappings)
    routes = mappings.fetch('routes').select { |row| SELECTORS.all? { |key| row[key] == input[key] } }
    raise ArgumentError, 'intake_route_unmapped' unless routes.one?

    value = JrcServiceDesk::Input.attributes(routes.first, SELECTORS + %w[entity_id category_id group_id requester_policy sla slas
                                                                          creation_attributes request_type_id requester_approved priority])
    value['entity_id'] = JrcServiceDesk::Glpi::Identifiers.remote(value.fetch('entity_id'))
    %w[category_id group_id].each { |key| value[key] = JrcServiceDesk::Input.id(value.fetch(key)) }
    validate_creation_policy!(value)
    validate_priority!(value) if value.key?('priority')
    validate_requester_policy!(value)
    validate_route_slas!(value) if value.key?('slas')
    value
  end

  def validate_creation_policy!(value)
    raise ArgumentError, 'intake_sla_conflict' if value.key?('sla') && value.key?('slas')

    if (value.key?('slas') || value.key?('request_type_id')) && value['creation_attributes'] != true
      raise ArgumentError, 'intake_creation_attributes_required'
    end

    JrcServiceDesk::Input.id(value['request_type_id']) if value.key?('request_type_id')
  end

  def validate_priority!(value)
    valid = value['creation_attributes'] == true && value['reason'] == 'bug' &&
            %w[low medium high critical].include?(value['severity']) &&
            value['priority'].is_a?(Integer) && value['priority'].between?(1, 6)
    raise ArgumentError, 'intake_priority_unmapped' unless valid
  end

  def validate_requester_policy!(value)
    unless value['requester_policy'] == 'mapped_contact' ||
           (%w[email_only email_or_anonymous].include?(value['requester_policy']) && value['requester_approved'] == true)
      raise ArgumentError, 'intake_requester_policy_unapproved'
    end
  end

  def validate_route_slas!(value)
    slas = JrcServiceDesk::Input.attributes(value['slas'], %w[own resolve])
    raise ArgumentError, 'intake_sla_unmapped' if slas.empty?

    slas.each do |purpose, sla|
      raise ArgumentError, 'intake_sla_unmapped' unless sla.is_a?(Hash) && sla['purpose'] == purpose
    end
  end

  def resolve_requester(mappings, contact_id)
    raise ArgumentError, 'intake_requester_unmapped' unless route['requester_policy'] == 'mapped_contact'

    requesters = mappings.fetch('requesters').select do |row|
      row['contact_id'].to_s == contact_id.to_s && row['entity_id'].to_s == route['entity_id'].to_s
    end
    raise ArgumentError, 'intake_requester_unmapped' unless requesters.one?

    JrcServiceDesk::Input.id(requesters.first.fetch('user_id'))
  end

  def preflight!(access:, client:, resolve_requester: true)
    resolve_email_requester!(access, client) if resolve_requester && route['requester_policy'] != 'mapped_contact'
    raise Pundit::NotAuthorizedError unless access.context.capability?(:lookups_view)

    validate_group!(access, client)
    sla_definitions.each do |sla, expected|
      JrcServiceDesk::Glpi::IntakeSla.new.validate!(access: access, client: client, entity_id: route.fetch('entity_id'),
                                                    mapping: sla.except('expected'), expected: expected)
    end
    validate_request_type!(client) if route['request_type_id']
  end

  def resolve_email_requester!(access, client)
    @requester_attributes = JrcServiceDesk::Intake::Requester.new.resolve!(
      access: access, client: client, entity_id: route.fetch('entity_id'), email: input.fetch('email'),
      policy: route.fetch('requester_policy')
    )
    @requester_id = @requester_attributes.fetch('_users_id_requester')
  end

  def validate_group!(access, client)
    group = client.get("Group/#{route.fetch('group_id')}")
    raise JrcServiceDesk::Glpi::Error, 'invalid_response' unless group['id'].to_s == route['group_id'].to_s

    JrcServiceDesk::Glpi::MetadataScope.new(access: access, client: client, entity_id: route.fetch('entity_id')).authorize!('Group', group)
    return if [1, '1', true].include?(group['is_assign']) && [1, '1', true].exclude?(group['is_deleted'])

    raise JrcServiceDesk::Glpi::Error.new('intake_group_unavailable', 422)
  end

  def validate_request_type!(client)
    origin = client.get("RequestType/#{route.fetch('request_type_id')}")
    return if origin['id'].to_s == route['request_type_id'].to_s && [1, '1', true].exclude?(origin['is_deleted'])

    raise JrcServiceDesk::Glpi::Error.new('intake_origin_unavailable', 422)
  end

  def attributes
    values = { 'name' => "#{input.fetch('system')} / #{input.fetch('subject_label')}".first(255),
               'content' => content,
               'type' => input['reason'] == 'bug' ? 1 : 2, 'urgency' => input.fetch('urgency_value', 3), 'impact' => input.fetch('impact_value', 3),
               'itilcategories_id' => route.fetch('category_id'), '_users_id_requester' => requester_id }
    unless route['requester_policy'] == 'mapped_contact'
      raise ArgumentError, 'intake_requester_unresolved' unless @requester_attributes

      values.merge!(@requester_attributes)
    end
    values.merge!(creation_values) if creation_attributes?
    values
  end

  def creation_values
    values = { '_groups_id_assign' => route.fetch('group_id') }.merge(sla_attributes || {}).merge(route.slice('priority'))
    values['requesttypes_id'] = route['request_type_id'] if route['request_type_id']
    values
  end

  def content
    "#{input.fetch('description')}\n\n#{input.fetch('identifier_type')}: #{input.fetch('identifier')}\n" \
      "Email: #{input.fetch('email')}\n#{SELECTORS.map { |key| "#{key}: #{input[key]}" }.join("\n")}"
  end

  def sla_attributes
    if route.key?('slas')
      return sla_definitions.to_h do |sla, _expected|
        [sla.fetch('purpose') == 'resolve' ? 'slas_id_ttr' : 'slas_id_tto', JrcServiceDesk::Input.id(sla.fetch('id'))]
      end
    end
    return nil if input.fetch('sla').fetch('unit') == 'none'

    sla = route.fetch('sla')
    { (sla.fetch('purpose') == 'resolve' ? 'slas_id_ttr' : 'slas_id_tto') => JrcServiceDesk::Input.id(sla.fetch('id')) }
  end

  def creation_attributes? = route['creation_attributes'] == true

  def sla_definitions
    JrcServiceDesk::Intake::SlaMapping.new(route, input.fetch('sla')).definitions
  end
end
