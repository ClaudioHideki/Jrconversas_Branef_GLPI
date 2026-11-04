# frozen_string_literal: true

class JrcServiceDesk::GlpiSyncRun < JrcServiceDesk::AccountRecord
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  belongs_to :account_user
  validates :state, inclusion: { in: %w[running complete partial failed] }
  validates :connection_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate do
    %i[glpi_connection account_user].each { |name| validate_account_reference(name) }
  end

  def receipt
    { id: id.to_s, state: state, dataset: 'tickets', coverage: coverage, started_at: created_at.iso8601,
      finished_at: finished_at&.iso8601, connection_version: connection_version }
  end
end
