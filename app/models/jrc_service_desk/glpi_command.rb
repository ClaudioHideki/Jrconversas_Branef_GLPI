# frozen_string_literal: true

class JrcServiceDesk::GlpiCommand < JrcServiceDesk::AccountRecord
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  belongs_to :account_user
  belongs_to :unit, class_name: 'JrcServiceDesk::Unit'
  validates :idempotency_key, :fingerprint, :state, presence: true
  validates :state, inclusion: { in: %w[pending sending succeeded rejected indeterminate] }
  validate do
    %i[glpi_connection account_user unit].each { |name| validate_account_reference(name) }
  end

  def receipt
    { id: id.to_s, state: state, remote_id: remote_id&.to_s, error_code: error_code, updated_at: updated_at.iso8601 }
  end

  def correlation_marker
    "JRC: #{account_id}/#{id}/#{correlation_id}"
  end
end
