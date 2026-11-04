# frozen_string_literal: true

class JrcServiceDesk::Glpi::Access
  attr_reader :context, :connection

  def initialize(user_context)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.capability?(:tickets_view)

    @connection = JrcServiceDesk::GlpiConnection.find_by(account_id: context.account.id)
  end

  def ready!
    raise JrcServiceDesk::Glpi::Error.new('not_configured', 422) unless connection&.enabled?
    raise Pundit::NotAuthorizedError if mappings.empty? || (!all_tickets? && glpi_user_id.nil?)

    self
  end

  def mappings
    return [] unless connection

    units = context.unit_scope.pluck(:id)
    connection.entity_mappings.select do |row|
      units.include?(JrcServiceDesk::Input.id(row.fetch('unit_id'))) &&
        !context.supervision_access.restricted?(JrcServiceDesk::Input.id(row.fetch('unit_id')))
    end
  end

  def entity_ids
    mappings.map { |row| JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('entity_id')) }
  end

  def unit_for(entity)
    row = mappings.find { |item| JrcServiceDesk::Glpi::Identifiers.remote(item.fetch('entity_id')) == entity }
    raise Pundit::NotAuthorizedError unless row

    JrcServiceDesk::Input.id(row.fetch('unit_id'))
  end

  def glpi_user_id
    row = connection&.user_mappings&.find { |item| JrcServiceDesk::Input.id(item.fetch('account_user_id')) == context.account_user.id }
    row && JrcServiceDesk::Input.id(row.fetch('glpi_user_id'))
  end

  def all_tickets?
    context.capability?(:tickets_view_all)
  end

  def authorize_ticket!(client, ticket)
    unit_for(JrcServiceDesk::Glpi::Identifiers.remote(ticket.fetch('entities_id')))
    return if all_tickets?

    id = JrcServiceDesk::Input.id(ticket.fetch('id'))
    actors = client.collection("Ticket/#{id}/Ticket_User/")
    authorized = actors.any? do |actor|
      raise Pundit::NotAuthorizedError unless actor['tickets_id'].to_s == id.to_s

      actor['users_id'].to_s == glpi_user_id.to_s && [1, 2].include?(actor['type'].to_i)
    end
    raise Pundit::NotAuthorizedError unless authorized
  end
end
