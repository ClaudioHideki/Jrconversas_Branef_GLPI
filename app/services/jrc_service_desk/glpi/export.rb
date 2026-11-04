# frozen_string_literal: true

require 'csv'
require 'tempfile'
require 'digest'

class JrcServiceDesk::Glpi::Export
  class Cancelled < StandardError; end

  def self.maximum_bytes
    # Operational storage quota, never a successful truncated result.
    Integer(ENV.fetch('GLPI_EXPORT_MAX_BYTES', 100.megabytes.to_s))
  end

  def prepare(access:, filters:)
    access = fresh_access(access)
    data = selection(access, filters)
    record = JrcServiceDesk::GlpiExport.create!(account: access.context.account, glpi_connection: access.connection,
      account_user: access.context.account_user, connection_version: access.connection.lock_version,
      filters: data.query.filters.except('page', 'per_page'), scope: scope_signature(data), coverage: data.coverage,
      total: data.scope.count)
    audit(record, 'glpi_export_prepared', access)
    JrcServiceDesk::GlpiExportJob.perform_later(record.id)
    record
  end

  def status(access:, id:)
    record = find_record(access, id)
    authorize_record(record, access)
    expire(id: record.id) if record.expires_at && record.expires_at <= Time.current
    record.reload
  rescue Pundit::NotAuthorizedError, JrcServiceDesk::Glpi::Error => error
    fail_record(record, error) if record
    raise
  end

  def cancel(access:, id:)
    record = find_record(access, id)
    current = authorize_record(record, access)
    record.with_lock do
      record.update!(state: 'cancelled', verification_expires_at: nil, verification_nonce: nil) unless record.state == 'expired'
    end
    record.artifact.purge
    audit(record, 'glpi_export_cancelled', current)
    record
  rescue Pundit::NotAuthorizedError, JrcServiceDesk::Glpi::Error => error
    fail_record(record, error) if record
    raise
  end

  def generate(id:, client: nil)
    record = JrcServiceDesk::GlpiExport.find(id)
    return record unless claim(record, 'queued', 'running')

    current = authorize_record(record)
    data = selection(current, record.filters)
    validate_scope(record, data)
    manifest = []
    fields = JrcServiceDesk::Glpi::Normalize::FIELDS.values
    Tempfile.create(['glpi-export-', '.csv']) do |file|
      csv = CSV.new(file)
      csv << fields.map { |field| JrcServiceDesk::OperationalCsv.cell(field) }
      with_client(current, client) do |source|
        JrcServiceDesk::Glpi::TicketQuery.new(current, record.filters).each_batch(source) do |batch, progress|
          current = authorize_record(record)
          ensure_running(record, 'running')
          expected = data.scope.where(remote_id: batch.map { |row| row.fetch('id') })
            .pluck(:remote_id, :entity_id, Arel.sql("COALESCE(payload->>'date_mod', payload->>'updated_at')")).to_h do |remote_id, entity_id, revision|
              [remote_id, { 'id' => remote_id, 'entity_id' => entity_id, 'revision' => revision }]
            end
          batch.each do |row|
            entry = expected.delete(JrcServiceDesk::Input.id(row.fetch('id')))
            raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless entry

            verify_ticket(source, current, entry)
            csv << fields.map { |key| JrcServiceDesk::OperationalCsv.cell(row[key]) }
            entry['row_hash'] = row_hash(row)
            manifest << entry
            raise JrcServiceDesk::Glpi::Error.new('export_quota', 422) if file.pos > self.class.maximum_bytes
          end
          update_progress(record, 'running', progress)
        end
      end
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless manifest.size == record.total

      file.flush
      raise JrcServiceDesk::Glpi::Error.new('export_quota', 422) if file.size > self.class.maximum_bytes

      file.rewind
      record.artifact.attach(io: file, filename: 'glpi-tickets.csv', content_type: 'text/csv')
      record.with_lock do
        authorize_record(record)
        raise Cancelled unless record.state == 'running'

        completed = Time.current
        record.update!(state: 'ready', processed: manifest.size, manifest: manifest, finished_at: completed, expires_at: completed + 24.hours)
      end
    end
    JrcServiceDesk::GlpiExportJob.set(wait_until: record.expires_at).perform_later(record.id, 'expire')
    audit(record, 'glpi_export_generated', current, count: record.processed)
    record
  rescue Cancelled
    record.artifact.purge
    record
  rescue StandardError => error
    raise unless record

    fail_record(record, error)
    record
  end

  # Preparing the one-use proof is deliberately a background operation: source
  # detail rights must be checked for every record, not sampled or cached forever.
  def verify(id:, client: nil)
    record = JrcServiceDesk::GlpiExport.find(id)
    return record unless record.state == 'verifying'

    current = authorize_record(record)
    ensure_unexpired(record)
    validate_scope(record, selection(current, record.filters))
    expected = record.manifest.index_by { |entry| entry.fetch('id') }
    from = Time.current
    identity = nil
    with_client(current, client) do |source|
      identity = source_identity(source, record.scope.fetch('entity_ids'))
      JrcServiceDesk::Glpi::TicketQuery.new(current, record.filters).each_batch(source) do |batch, progress|
        current = authorize_record(record)
        ensure_running(record, 'verifying')
        batch.each do |row|
          entry = expected.delete(JrcServiceDesk::Input.id(row.fetch('id')))
          raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless entry && entry['row_hash'] == row_hash(row)

          verify_ticket(source, current, entry)
        end
        update_progress(record, 'verifying', progress)
      end
    end
    raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless expected.empty? && record.processed == record.total

    record.with_lock do
      authorize_record(record)
      ensure_unexpired(record)
      raise Cancelled unless record.state == 'verifying'

      record.update!(state: 'ready', verified_from: from, verified_until: Time.current,
        verification_expires_at: 30.seconds.from_now, verification_nonce: SecureRandom.uuid, source_identity: identity)
    end
    record
  rescue Cancelled
    record
  rescue StandardError => error
    raise unless record

    fail_record(record, error)
    record
  end

  # A record with state=verifying is a 202 receipt, never an attachment. Root's
  # authenticated controller only sends the file after this method consumes a
  # proof and returns ready. Storage's signed/public URLs must not be exposed.
  def download(access:, id:)
    record = find_record(access, id)
    current = authorize_record(record, access)
    if record.expires_at && record.expires_at <= Time.current
      expire(id: record.id)
      raise JrcServiceDesk::Glpi::Error.new('export_expired', 410)
    end
    if record.state == 'failed'
      status = record.error_http_status || (record.error_code == 'access_revoked' ||
        record.error_code.to_s.start_with?('ERROR_RIGHT', 'ERROR_SESSION') ? 403 : 409)
      raise JrcServiceDesk::Glpi::Error.new(record.error_code, status)
    end
    return record if record.state == 'verifying'
    raise JrcServiceDesk::Glpi::Error.new('export_not_ready', 409) unless record.state == 'ready' && record.artifact.attached?

    # Bind each bounded source probe to the exact proof it observed. A worker
    # may publish another proof before lock! reloads this row; that new proof
    # must be probed independently, even if its timestamps happen to be equal.
    2.times do
      observed_nonce = usable_proof?(record) ? record.verification_nonce.dup : nil
      if observed_nonce
        with_client(current, nil) do |source|
          unless source_identity(source, record.scope.fetch('entity_ids')) == record.source_identity
            raise JrcServiceDesk::Glpi::Error.new('source_changed', 409)
          end
          verify_ticket(source, current, record.manifest.first) if record.manifest.any?
        end
      end
      outcome = :retry
      record.with_lock do
        current = authorize_record(record, access)
        ensure_unexpired(record)
        if record.state == 'ready' && usable_proof?(record)
          if observed_nonce && record.verification_nonce == observed_nonce
            record.update!(verification_expires_at: nil, verification_nonce: nil)
            outcome = :claimed
          end
        elsif record.state == 'ready'
          record.update!(state: 'verifying', processed: 0, verified_from: nil, verified_until: nil,
            verification_expires_at: nil, verification_nonce: nil)
          JrcServiceDesk::GlpiExportJob.perform_later(record.id, 'verify')
          outcome = :pending
        elsif record.state == 'verifying'
          outcome = :pending
        elsif record.state == 'failed'
          raise JrcServiceDesk::Glpi::Error.new(record.error_code, record.error_http_status || 409)
        else
          raise JrcServiceDesk::Glpi::Error.new('export_not_ready', 409)
        end
      end
      return record if outcome == :pending
      next unless outcome == :claimed

      audit(record, 'glpi_export_downloaded', current, count: record.total)
      return record
    end
    # Continuous proof rotation is recoverable. Preserve the artifact and the
    # newly published proof, but never deliver bytes using a previous probe.
    raise JrcServiceDesk::Glpi::Error.new('export_verification_changed', 409)
  rescue Pundit::NotAuthorizedError, JrcServiceDesk::Glpi::Error => error
    pending = error.respond_to?(:code) && error.code == 'export_not_ready' && record && %w[queued running].include?(record.state)
    changed = error.respond_to?(:code) && error.code == 'export_verification_changed'
    fail_record(record, error) if record && record.state != 'expired' && !pending && !changed
    raise
  end

  def expire(id:)
    record = JrcServiceDesk::GlpiExport.find(id)
    record.with_lock do
      return record unless record.expires_at && record.expires_at <= Time.current

      record.update!(state: 'expired', verification_expires_at: nil, verification_nonce: nil)
    end
    record.artifact.purge
    record
  end

  private

  def usable_proof?(record)
    record.verification_nonce.present? && record.verification_expires_at&.future?
  end

  def fresh_access(access)
    current = JrcServiceDesk::Glpi::Access.new(access.context.to_h).ready!
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::GlpiPolicy.new(current.context.to_h, :glpi).export?

    current
  end

  def find_record(access, id)
    JrcServiceDesk::GlpiExport.where(account_id: access.context.account.id,
      glpi_connection_id: access.connection&.id, account_user_id: access.context.account_user.id).find(JrcServiceDesk::Input.id(id))
  end

  def authorize_record(record, access = nil)
    member = AccountUser.find_by(id: record.account_user_id, account_id: record.account_id)
    raise Pundit::NotAuthorizedError unless member

    identity = { account: record.account, user: member.user, account_user: member }
    current = fresh_access(access || JrcServiceDesk::Glpi::Access.new(identity))
    unless current.connection.id == record.glpi_connection_id && current.context.account_user.id == record.account_user_id
      raise Pundit::NotAuthorizedError
    end
    unless current.connection.lock_version == record.connection_version
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end
    unless (record.scope.fetch('entity_ids') - current.entity_ids).empty?
      raise Pundit::NotAuthorizedError
    end
    current
  end

  def ensure_unexpired(record)
    return unless record.expires_at && record.expires_at <= Time.current

    expire(id: record.id)
    raise JrcServiceDesk::Glpi::Error.new('export_expired', 410)
  end

  def selection(access, filters)
    data = JrcServiceDesk::Glpi::Overview.new.selection(access: access, filters: filters)
    raise JrcServiceDesk::Glpi::Error.new('export_coverage_incomplete', 422) unless data.coverage[:state] == 'complete'

    data
  end

  def scope_signature(data)
    { 'entity_ids' => data.query.entity_ids.sort, 'run_id' => data.coverage[:run_id],
      'mine' => data.query.mine?, 'glpi_user_id' => data.query.mine? ? data.access.glpi_user_id : nil }
  end

  def validate_scope(record, data)
    unless record.scope == scope_signature(data) && data.scope.count == record.total
      raise JrcServiceDesk::Glpi::Error.new('projection_changed', 409)
    end
  end

  def with_client(access, client, &block)
    return yield client if client

    JrcServiceDesk::Glpi::Client.new(access.connection).session(&block)
  end

  def verify_ticket(source, access, entry)
    detail = source.get("Ticket/#{entry.fetch('id')}")
    entity = JrcServiceDesk::Glpi::Identifiers.remote(detail.fetch('entities_id'))
    unless entity == entry.fetch('entity_id') && JrcServiceDesk::Input.id(detail.fetch('id')) == entry.fetch('id')
      raise JrcServiceDesk::Glpi::Error.new('entity_mismatch', 409)
    end
    access.authorize_ticket!(source, detail)
    # An absent revision cannot prove that the cached export is still current.
    unless entry['revision'].present? && detail['date_mod'].present? && detail['date_mod'] == entry['revision']
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409)
    end
  end

  def source_identity(source, entities)
    profile = source.get('getActiveProfile/').fetch('active_profile')
    actual = source.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
      .map { |entity| JrcServiceDesk::Glpi::Identifiers.remote(entity.fetch('id')) }
    raise Pundit::NotAuthorizedError unless (entities - actual).empty?

    { 'profile_sha256' => Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.dump(profile)), 'entity_ids' => actual.sort }
  end

  def row_hash(row)
    Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.dump(row))
  end

  def claim(record, from, to)
    record.with_lock do
      return false unless record.state == from

      record.update!(state: to, processed: 0)
    end
    true
  end

  def ensure_running(record, state)
    raise Cancelled unless record.reload.state == state
  end

  def update_progress(record, state, progress)
    record.with_lock do
      raise Cancelled unless record.state == state
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless progress[:total] == record.total

      record.update!(processed: progress[:processed])
    end
  end

  def fail_record(record, error)
    code = error.is_a?(Pundit::NotAuthorizedError) || error.is_a?(ActiveRecord::RecordNotFound) ? 'access_revoked' :
      error.respond_to?(:code) ? error.code : 'export_failed'
    status = code == 'access_revoked' ? 403 : error.respond_to?(:http_status) ? error.http_status : 500
    record.with_lock do
      record.update!(state: 'failed', error_code: code, error_http_status: status,
        verification_expires_at: nil, verification_nonce: nil) unless %w[cancelled expired].include?(record.state)
    end
    record.artifact.purge
    Rails.logger.warn("GLPI export #{record.id} failed (#{code})")
  end

  def audit(record, action, access, metadata = {})
    Audited::Audit.create!(auditable: record, user: access.context.user, action: action, audited_changes: {},
      comment: JrcServiceDesk::CanonicalJson.dump(metadata.merge(account_id: record.account_id,
        operator_account_user_id: record.account_user_id, effective_identity: 'glpi_integration_technical_user')),
      request_uuid: SecureRandom.uuid)
  end
end
