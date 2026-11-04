# frozen_string_literal: true

class JrcServiceDesk::Glpi::Detail
  def call(access:, client:, ticket_id:)
    query = JrcServiceDesk::Glpi::ResourceQuery.new
    ticket = query.raw(access: access, client: client, kind: 'tickets', id: ticket_id)
    history = JrcServiceDesk::Glpi::ResourceQuery::CHILD_TYPES.to_h do |kind, type|
      begin
        result = query.related(access: access, client: client, kind: kind, ticket_id: ticket.fetch('id'))
        [type, result.merge(available: true)]
      rescue JrcServiceDesk::Glpi::Error => e
        [type, { available: false, error_code: e.code }]
      rescue Pundit::NotAuthorizedError
        [type, { available: false, error_code: 'access_denied' }]
      end
    end
    { ticket: JrcServiceDesk::Glpi::Normalize.detail(ticket), history: history,
      source_version: ticket['date_mod'], generated_at: Time.current.iso8601 }
  end
end
