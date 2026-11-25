# frozen_string_literal: true

class JrcServiceDesk::GlpiSentimentBatch < JrcServiceDesk::AccountRecord
  ACTIVE_STATES = %w[queued running cancelling].freeze

  belongs_to :account_user
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  has_many :items, class_name: 'JrcServiceDesk::GlpiSentimentItem', foreign_key: :batch_id, inverse_of: :batch, dependent: :delete_all

  validate do
    %i[glpi_connection account_user].each { |name| validate_account_reference(name) }
  end

  scope :active, -> { where(state: ACTIVE_STATES) }

  def receipt
    counts = items.group(:state).count
    { id: id.to_s, state: state, total: total, counts: counts,
      processed: counts.values_at('analyzed', 'no_public_text', 'failed').compact.sum, filters: filters, error: error,
      created_at: created_at.iso8601, coverage: coverage }
  end
end
