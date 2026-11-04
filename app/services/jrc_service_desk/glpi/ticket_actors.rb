# frozen_string_literal: true

class JrcServiceDesk::Glpi::TicketActors
  def call(client:, ticket_id:)
    raise ArgumentError unless ticket_id.to_s.match?(/\A[1-9]\d*\z/)

    requester = []
    assigned = []
    client.collection("Ticket/#{ticket_id}/Ticket_User/").each do |row|
      unless row['tickets_id'].to_s == ticket_id.to_s && row['users_id'].to_s.match?(/\A\d+\z/)
        raise JrcServiceDesk::Glpi::Error.new('invalid_actor_scope')
      end
      user_id = row['users_id'].to_i
      next if user_id.zero?

      requester << user_id if row['type'].to_i == 1
      assigned << user_id if row['type'].to_i == 2
    end
    { 'actor_scope_available' => true, 'actor_user_ids' => (requester + assigned).uniq.sort,
      'requester_user_ids' => requester.uniq.sort, 'assigned_user_ids' => assigned.uniq.sort }
  rescue JrcServiceDesk::Glpi::Error => e
    { 'actor_scope_available' => false, 'actor_scope_error' => e.code, 'actor_user_ids' => nil,
      'requester_user_ids' => nil, 'assigned_user_ids' => nil }
  end
end
