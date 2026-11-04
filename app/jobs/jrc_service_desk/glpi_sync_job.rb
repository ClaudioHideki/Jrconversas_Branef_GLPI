# frozen_string_literal: true

class JrcServiceDesk::GlpiSyncJob < ApplicationJob
  queue_as :low

  def perform(connection_id, account_user_id)
    connection = JrcServiceDesk::GlpiConnection.find(connection_id)
    actor = AccountUser.where(account_id: connection.account_id).find(account_user_id)
    JrcServiceDesk::Glpi::SyncTickets.new.call(connection: connection, actor: actor)
  end
end
