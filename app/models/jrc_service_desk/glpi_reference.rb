# frozen_string_literal: true

class JrcServiceDesk::GlpiReference < JrcServiceDesk::UnitRecord
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  validates :itemtype, inclusion: { in: %w[Ticket Problem Change KnowbaseItem] }
  validates :remote_id, numericality: { only_integer: true, greater_than: 0 }
  validates :entity_id, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate { validate_account_reference(:glpi_connection) }

  def reference
    { 'account_id' => account_id, 'connection_id' => glpi_connection_id, 'itemtype' => itemtype,
      'remote_id' => remote_id, 'entity_id' => entity_id }
  end

  protected

  def ownership_columns
    super + %i[glpi_connection_id itemtype remote_id entity_id]
  end
end
