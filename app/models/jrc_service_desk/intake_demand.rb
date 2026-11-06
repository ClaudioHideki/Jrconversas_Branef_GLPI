# frozen_string_literal: true

class JrcServiceDesk::IntakeDemand < JrcServiceDesk::AccountRecord
  STATES = %w[qualified queued sending confirmed partial rejected indeterminate test_only].freeze
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :contact
  belongs_to :account_user
  belongs_to :intake_configuration, class_name: 'JrcServiceDesk::IntakeConfiguration'
  serialize :normalized_input, coder: JSON
  encrypts :normalized_input, support_unencrypted_data: false
  validates :episode_key, presence: true, uniqueness: { scope: :account_id }
  validates :fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :state, inclusion: { in: STATES }
  validate :conversation_identity_matches
  validate do
    %i[inbox conversation contact account_user intake_configuration].each { |name| validate_account_reference(name) }
  end

  def receipt(created: false)
    { id: id.to_s, episode_key: episode_key, configuration_id: intake_configuration_id.to_s,
      state: state, created: created, remote_id: remote_id&.to_s,
      error_code: error_code, stages: delivery_receipts }
  end

  protected

  def ownership_columns
    super + %i[inbox_id conversation_id contact_id account_user_id intake_configuration_id episode_key]
  end

  private

  def conversation_identity_matches
    expected = [inbox_id, contact_id]
    records = [conversation, conversation&.contact_inbox]
    valid = records.all? { |record| record && expected == [record.inbox_id, record.contact_id] } &&
            intake_configuration&.inbox_id == inbox_id
    errors.add(:base, 'intake conversation identity mismatch') unless valid
  end
end
