# frozen_string_literal: true

class JrcServiceDesk::GlpiSyncJob < ApplicationJob
  queue_as :low

  def perform(connection_id, account_user_id, run_id = nil)
    connection = JrcServiceDesk::GlpiConnection.find(connection_id)
    actor = AccountUser.where(account_id: connection.account_id).find(account_user_id)
    run = run_id && JrcServiceDesk::GlpiSyncRun.where(account_id: connection.account_id, glpi_connection: connection).find(run_id)
    JrcServiceDesk::Glpi::SyncTickets.new.call(connection: connection, actor: actor, run: run)
  end
end
