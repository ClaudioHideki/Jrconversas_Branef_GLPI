# frozen_string_literal: true

# A numeric remote ID alone never identifies a Service Desk record.
class JrcServiceDesk::Glpi::Reference
  KINDS = { 'Ticket' => 'tickets', 'Problem' => 'problems', 'Change' => 'changes', 'KnowbaseItem' => 'knowledge' }.freeze
  FIELDS = %w[account_id connection_id itemtype remote_id entity_id].freeze
  attr_reader :values

  def initialize(value)
    @values = JrcServiceDesk::Input.attributes(value, FIELDS)
    raise ArgumentError unless (FIELDS - values.keys).empty? && KINDS.key?(values['itemtype'])

    %w[account_id connection_id remote_id].each { |key| values[key] = JrcServiceDesk::Input.id(values[key]) }
    values['entity_id'] = JrcServiceDesk::Glpi::Identifiers.remote(values['entity_id'])
    values.freeze
  end

  def identity_key
    "glpi/#{FIELDS.map { |field| values.fetch(field) }.join('/')}"
  end

  def authorize!(access:, client:, operational: false)
    fresh = JrcServiceDesk::Glpi::Access.new(access.context.to_h).ready!
    unless fresh.context.account.id == values['account_id'] && fresh.connection.id == values['connection_id'] &&
           fresh.connection.primary_source?
      raise Pundit::NotAuthorizedError
    end
    unit = fresh.context.unit_scope.find(fresh.unit_for(values['entity_id']))
    raise Pundit::NotAuthorizedError if operational && !fresh.context.operational_unit_allowed?(unit)

    row = JrcServiceDesk::Glpi::ResourceQuery.new.raw(access: fresh, client: client,
      kind: KINDS.fetch(values['itemtype']), id: values['remote_id'])
    if values['itemtype'] == 'KnowbaseItem'
      visible = client.collection("KnowbaseItem/#{values['remote_id']}/Entity_KnowbaseItem/").any? do |link|
        link['knowbaseitems_id'].to_s == values['remote_id'].to_s && link['entities_id'].to_s == values['entity_id'].to_s
      end
      raise Pundit::NotAuthorizedError unless visible
    elsif row['entities_id'].to_s != values['entity_id'].to_s
      raise Pundit::NotAuthorizedError
    end
    row
  end

  def record!(access:, client:)
    authorize!(access: access, client: client)
    JrcServiceDesk::GlpiReference.find_or_create_by!(account_id: values['account_id'], glpi_connection_id: values['connection_id'],
      itemtype: values['itemtype'], remote_id: values['remote_id'], entity_id: values['entity_id']) do |record|
      record.unit_id = access.unit_for(values['entity_id'])
    end
  end
end
