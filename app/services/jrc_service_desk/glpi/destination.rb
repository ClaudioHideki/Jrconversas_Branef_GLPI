# frozen_string_literal: true

# Creation binds an authenticated account/connection revision/entity, not an invented remote ID.
class JrcServiceDesk::Glpi::Destination
  attr_reader :values

  def initialize(value)
    @values = JrcServiceDesk::Input.attributes(value, %w[connection_id connection_version entity_id])
    values['connection_id'] = JrcServiceDesk::Input.id(values.fetch('connection_id'))
    values['connection_version'] = JrcServiceDesk::Input.version(values.fetch('connection_version'))
    values['entity_id'] = JrcServiceDesk::Glpi::Identifiers.remote(values.fetch('entity_id'))
  end

  def access!(user_context)
    access = JrcServiceDesk::Glpi::Access.new(user_context).ready!
    raise Pundit::NotAuthorizedError unless access.connection.primary_source? && access.connection.id == values['connection_id']
    unless access.connection.lock_version == values['connection_version']
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end
    unit = access.context.unit_scope.find(access.unit_for(values['entity_id']))
    unless access.context.capability?(:tickets_create) && access.context.operational_unit_allowed?(unit)
      raise Pundit::NotAuthorizedError
    end
    access
  end

end
