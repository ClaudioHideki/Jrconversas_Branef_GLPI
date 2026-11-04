# frozen_string_literal: true

class JrcServiceDesk::GlpiCommand < JrcServiceDesk::AccountRecord
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  belongs_to :account_user
  belongs_to :unit, class_name: 'JrcServiceDesk::Unit'
  serialize :request_payload, coder: JSON
  serialize :before_values, coder: JSON
  serialize :template_policy, coder: JSON
  encrypts :request_payload, support_unencrypted_data: false
  encrypts :before_values, support_unencrypted_data: false
  encrypts :template_policy, support_unencrypted_data: false
  encrypts :reason, support_unencrypted_data: false
  validates :idempotency_key, :fingerprint, :state, presence: true
  validates :state, inclusion: { in: %w[pending sending succeeded rejected indeterminate] }
  validate do
    %i[glpi_connection account_user unit].each { |name| validate_account_reference(name) }
  end

  def receipt
    { id: id.to_s, connection_id: glpi_connection_id.to_s, connection_version: connection_version,
      state: state, operation: operation, itemtype: itemtype, target_id: target_id&.to_s, template_version: template_version,
      parent_id: parent_id&.to_s, parent_type: parent_type, entity_id: entity_id.to_s,
      remote_id: remote_id&.to_s, technical_user_id: technical_user_id, initiator_account_user_id: account_user_id.to_s,
      error_code: error_code, result: result, updated_at: updated_at.iso8601 }
  end

  def correlation_marker
    "JRC: #{account_id}/#{id}/#{correlation_id}"
  end
end
