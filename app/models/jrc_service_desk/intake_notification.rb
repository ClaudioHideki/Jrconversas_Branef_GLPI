# frozen_string_literal: true

class JrcServiceDesk::IntakeNotification < JrcServiceDesk::AccountRecord
  STATES = %w[blocked queued sending sent delivered read failed unknown].freeze
  self.filter_attributes += [:rendered_payload]
  belongs_to :intake_demand, class_name: 'JrcServiceDesk::IntakeDemand'
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :account_user
  belongs_to :message, optional: true
  encrypts :rendered_payload, support_unencrypted_data: false
  validates :state, inclusion: { in: STATES }
  validates :kind, inclusion: { in: %w[pending_information survey] }
  validates :channel, inclusion: { in: %w[whatsapp] }
  validates :request_key, :generation, format: { with: JrcServiceDesk::Intake::Submission::UUID }
  validate :references_match
  after_create_commit { JrcServiceDesk::IntakeNotificationJob.perform_later(id) if state == 'queued' }

  def receipt
    { id: id.to_s, kind: kind, channel: channel, state: state, reason_code: reason_code,
      message_id: message_id&.to_s, delivered_at: delivered_at&.iso8601 }
  end

  protected

  def ownership_columns
    super + %i[intake_demand_id inbox_id conversation_id account_user_id request_key generation kind channel template_code]
  end

  private

  def references_match
    %i[intake_demand inbox conversation account_user].each { |name| validate_account_reference(name) }
    validate_account_reference(:message) if message
    expected = [inbox_id, conversation_id]
    valid = intake_demand && expected == [intake_demand.inbox_id, intake_demand.conversation_id]
    valid &&= message_matches?
    errors.add(:base, 'intake notice identity mismatch') unless valid
  end

  def message_matches?
    message.nil? || (message.conversation_id == conversation_id && message.inbox_id == inbox_id)
  end
end
