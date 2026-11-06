# frozen_string_literal: true

# A publication selects the default for new flows without changing old snapshots.
class JrcServiceDesk::IntakeConfiguration < JrcServiceDesk::AccountRecord
  belongs_to :inbox
  belongs_to :created_by_account_user, class_name: 'AccountUser'
  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: [:account_id, :inbox_id] }
  validates :mode, inclusion: { in: %w[on_handoff on_qualification] }
  validates :enabled, :current, :remote_writes_enabled, inclusion: { in: [true, false] }
  validate :configuration_is_valid
  validate :snapshot_is_immutable, on: :update
  validate do
    validate_account_reference(:inbox)
    validate_account_reference(:created_by_account_user)
  end

  def public_configuration
    { id: id.to_s, revision: revision, inbox_id: inbox_id.to_s, catalogue: catalogue, responses: responses,
      mappings: mappings, mode: mode, enabled: enabled, current: current, remote_writes_enabled: remote_writes_enabled }
  end

  private

  def configuration_is_valid
    JrcServiceDesk::Intake::Catalogue.new(catalogue)
    raise ArgumentError unless responses.is_a?(Array) && responses.size <= 250 && responses.all?(Hash)

    validate_mappings!
  rescue ArgumentError, TypeError
    errors.add(:base, 'invalid intake configuration')
  end

  def validate_mappings!
    raise ArgumentError unless mappings.is_a?(Hash) && (mappings.keys - %w[routes requesters notifications]).empty?

    %w[routes requesters].each do |key|
      rows = mappings.fetch(key, [])
      raise ArgumentError unless rows.is_a?(Array) && rows.size <= 1000 && rows.all?(Hash)
    end
  end

  def snapshot_is_immutable
    columns = %w[inbox_id created_by_account_user_id revision catalogue responses mappings mode remote_writes_enabled]
    errors.add(:base, 'publish a new revision instead of changing a snapshot') if columns.any? { |column| will_save_change_to_attribute?(column) }
  end
end
