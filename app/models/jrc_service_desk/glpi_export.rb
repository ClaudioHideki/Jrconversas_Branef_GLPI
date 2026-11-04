# frozen_string_literal: true

class JrcServiceDesk::GlpiExport < JrcServiceDesk::AccountRecord
  belongs_to :glpi_connection, class_name: 'JrcServiceDesk::GlpiConnection'
  belongs_to :account_user
  has_one_attached :artifact
  validates :state, inclusion: { in: %w[queued running ready verifying failed cancelled expired] }
  validates :connection_version, :processed, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :error_http_status, numericality: { only_integer: true, greater_than_or_equal_to: 400, less_than_or_equal_to: 599 }, allow_nil: true
  validate do
    %i[glpi_connection account_user].each { |name| validate_account_reference(name) }
  end

  def receipt
    { id: id.to_s, state: state, processed: processed, total: total, error_code: error_code,
      created_at: created_at.iso8601, finished_at: finished_at&.iso8601, expires_at: expires_at&.iso8601,
      coverage: coverage, can_download: state == 'ready' && expires_at&.future? == true && verification_expires_at&.future? == true,
      verified_from: verified_from&.iso8601, verified_until: verified_until&.iso8601,
      verification_expires_at: verification_expires_at&.iso8601 }
  end
end
