# frozen_string_literal: true

class JrcServiceDesk::GlpiTicketSnapshot < JrcServiceDesk::AccountRecord
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  belongs_to :glpi_sync_run, class_name: 'JrcServiceDesk::GlpiSyncRun', optional: true
  belongs_to :unit, class_name: 'JrcServiceDesk::Unit'
  validates :remote_id, numericality: { only_integer: true, greater_than: 0 }
  validates :entity_id, :connection_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :observed_at, presence: true
  validate do
    %i[glpi_connection unit glpi_sync_run].each { |name| validate_account_reference(name) }
    next unless glpi_connection && unit

    mapped = glpi_connection.entity_mappings.any? { |row| row['entity_id'].to_i == entity_id && row['unit_id'].to_i == unit_id }
    errors.add(:entity_id, 'must have an explicit unit mapping') unless mapped
  end

  def self.current_for(connection)
    where(account_id: connection.account_id, glpi_connection_id: connection.id, connection_version: connection.lock_version, active: true)
  end
end
