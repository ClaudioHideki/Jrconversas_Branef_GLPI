# frozen_string_literal: true

class JrcServiceDesk::Intake::Mapping
  SELECTORS = %w[system location reason subject profile severity].freeze
  attr_reader :route, :requester_id, :destination, :input

  def initialize(demand)
    @input = demand.normalized_input
    mappings = demand.intake_configuration.mappings
    @route = resolve_route(mappings)
    @requester_id = resolve_requester(mappings, demand.contact_id)
    @destination = demand.source_context.slice('connection_id', 'connection_version').merge('entity_id' => route['entity_id'])
  end

  def resolve_route(mappings)
    routes = mappings.fetch('routes').select { |row| SELECTORS.all? { |key| row[key] == input[key] } }
    raise ArgumentError, 'intake_route_unmapped' unless routes.one?

    value = JrcServiceDesk::Input.attributes(routes.first, SELECTORS + %w[entity_id category_id group_id requester_policy sla])
    value['entity_id'] = JrcServiceDesk::Glpi::Identifiers.remote(value.fetch('entity_id'))
    %w[category_id group_id].each { |key| value[key] = JrcServiceDesk::Input.id(value.fetch(key)) }
    value
  end

  def resolve_requester(mappings, contact_id)
    raise ArgumentError, 'intake_requester_unmapped' unless route['requester_policy'] == 'mapped_contact'

    requesters = mappings.fetch('requesters').select do |row|
      row['contact_id'].to_s == contact_id.to_s && row['entity_id'].to_s == route['entity_id'].to_s
    end
    raise ArgumentError, 'intake_requester_unmapped' unless requesters.one?

    JrcServiceDesk::Input.id(requesters.first.fetch('user_id'))
  end

  def preflight!(access:, client:)
    query = JrcServiceDesk::Glpi::ResourceQuery.new
    group = query.raw(access: access, client: client, kind: 'groups', id: route.fetch('group_id'))
    unless [1, '1', true].include?(group['is_assign']) && [1, '1', true].exclude?(group['is_deleted'])
      raise JrcServiceDesk::Glpi::Error.new('intake_group_unavailable', 422)
    end
    return if input.fetch('sla').fetch('unit') == 'none' && route['sla'].nil?

    JrcServiceDesk::Glpi::IntakeSla.new.validate!(access: access, client: client, entity_id: route.fetch('entity_id'),
                                                  mapping: route.fetch('sla'), expected: input.fetch('sla'))
  end

  def attributes
    urgency = { 'low' => 2, 'medium' => 3, 'high' => 4, 'critical' => 5 }.fetch(input['severity'], 3)
    { 'name' => "#{input.fetch('system')} / #{input.fetch('subject_label')}".first(255),
      'content' => "#{input.fetch('description')}\n\n#{input.fetch('identifier_type')}: #{input.fetch('identifier')}\n" \
                   "Email: #{input.fetch('email')}\n#{SELECTORS.map { |key| "#{key}: #{input[key]}" }.join("\n")}",
      'type' => input['reason'] == 'bug' ? 1 : 2, 'urgency' => urgency, 'impact' => urgency,
      'itilcategories_id' => route.fetch('category_id'), '_users_id_requester' => requester_id }
  end

  def sla_attributes
    return nil if input.fetch('sla').fetch('unit') == 'none'

    sla = route.fetch('sla')
    { (sla.fetch('purpose') == 'resolve' ? 'slas_id_ttr' : 'slas_id_tto') => JrcServiceDesk::Input.id(sla.fetch('id')) }
  end
end
