# frozen_string_literal: true

class JrcServiceDesk::GlpiReferenceLink < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :glpi_reference, class_name: 'JrcServiceDesk::GlpiReference'
  # conversation_id is retained historical identity when the native target is
  # deleted; it is never an authorization grant or evidence the target is live.
  belongs_to :conversation, optional: true
  belongs_to :incident, class_name: 'JrcServiceDesk::Incident', optional: true
  belongs_to :account_user
  validate do
    validate_unit_reference(:glpi_reference)
    validate_unit_reference(:incident) if incident
    validate_account_reference(:conversation) if conversation
    validate_account_reference(:account_user)
    errors.add(:base, 'one local target required') unless conversation_id.nil? != incident_id.nil?
  end
end
