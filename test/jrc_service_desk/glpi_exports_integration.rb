# frozen_string_literal: true

require_relative 'glpi_test_helper'
require 'csv'

class GlpiExportsTest < GlpiIntegrationTest
  # Only HTTP is synthetic: permissions, memberships, receipts, jobs and storage are real.
  class Source
    attr_accessor :count, :denied, :duplicate, :change_total, :on_detail
    attr_reader :ranges

    def initialize(count = 3)
      @count = count
      @ranges = []
    end

    def session
      yield self
    end

    def get(path, parameters = {})
      if path == 'search/Ticket/'
        first, last = parameters.fetch('range').split('-').map(&:to_i)
        @ranges << [first, last]
        rows = (first...[last + 1, count].min).map do |index|
          { '2' => duplicate && index == 2 ? 1 : index + 1, '1' => index.zero? ? '=SUM(A1)' : "Ticket #{index + 1}",
            '80' => nil, '12' => 1, '3' => 3, '15' => '2026-01-01 10:00:00', '19' => '2026-01-02 10:00:00' }
        end
        return { 'data' => rows, 'totalcount' => change_total && first.positive? ? count + 1 : count }
      end
      id = path.delete_prefix('Ticket/').to_i
      on_detail&.call(id)
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403) if denied == id

      { 'id' => id, 'entities_id' => 0, 'date_mod' => '2026-01-02 10:00:00', 'status' => 1 }
    end
  end

  def service
    assert defined?(JrcServiceDesk::Glpi::Export), 'Missing durable asynchronous GLPI exports'
    JrcServiceDesk::Glpi::Export.new
  end

  def access
    JrcServiceDesk::Glpi::Access.new(@identity)
  end

  def seed_projection(count)
    @connection.update!(primary_source: true) unless @connection.primary_source?
    JrcServiceDesk::GlpiTicketSnapshot.where(glpi_connection: @connection).delete_all
    run = JrcServiceDesk::GlpiSyncRun.create!(account: @account, glpi_connection: @connection, account_user: @member,
      connection_version: @connection.lock_version, state: 'complete', finished_at: Time.current,
      coverage: { '0' => { state: 'complete', observed: count, indexed: count } })
    rows = count.times.map do |index|
      { account_id: @account.id, glpi_connection_id: @connection.id, unit_id: @unit.id, glpi_sync_run_id: run.id,
        remote_id: index + 1, entity_id: 0, connection_version: @connection.lock_version, observed_at: Time.current,
        payload: { 'id' => index + 1, 'entities_id' => 0, 'title' => index.zero? ? '=SUM(A1)' : "Ticket #{index + 1}",
          'status' => 1, 'priority' => 3, 'opened_at' => '2026-01-01 10:00:00', 'updated_at' => '2026-01-02 10:00:00' },
        active: true, created_at: Time.current, updated_at: Time.current }
    end
    JrcServiceDesk::GlpiTicketSnapshot.insert_all!(rows) if rows.any?
  end

  def prepare_export(count = 3)
    seed_projection(count)
    service.prepare(access: access, filters: {})
  end

  def test_complete_10205_rows_without_silent_cap_and_with_durable_progress
    record = prepare_export(10_205)
    assert_equal 'queued', record.state
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job] == JrcServiceDesk::GlpiExportJob && job[:args].first == record.id }
    source = Source.new(10_205)
    service.generate(id: record.id, client: source)
    record.reload
    assert_equal 'ready', record.state
    assert_equal 10_205, record.processed
    assert_equal 10_205, record.total
    assert_equal 10_206, CSV.parse(record.artifact.download).size
    assert_equal "'=SUM(A1)", CSV.parse(record.artifact.download)[1][1]
    assert_equal 0, record.manifest.first.fetch('entity_id')
    assert_equal 24.hours, record.expires_at - record.finished_at
    assert_operator source.ranges.size, :>, 50
  end

  def test_empty_export_has_only_header
    record = prepare_export(0)
    service.generate(id: record.id, client: Source.new(0))
    assert_equal 'ready', record.reload.state
    assert_equal 1, CSV.parse(record.artifact.download).size
  end

  def test_source_denial_mid_generation_never_delivers_partial_file
    record = prepare_export
    source = Source.new
    source.denied = 2
    service.generate(id: record.id, client: source)
    assert_equal 'failed', record.reload.state
    assert_equal 'ERROR_RIGHT_MISSING', record.error_code
    refute record.artifact.attached?
  end

  def test_duplicate_or_changing_page_count_is_failed_not_ready
    %i[duplicate change_total].each do |fault|
      record = prepare_export(205)
      source = Source.new(205)
      source.public_send("#{fault}=", true)
      service.generate(id: record.id, client: source)
      assert_equal 'failed', record.reload.state
      assert_equal 'source_changed', record.error_code
      refute record.artifact.attached?
    end
  end

  def test_quota_failure_never_becomes_truncated_export
    record = prepare_export
    JrcServiceDesk::Glpi::Export.stub(:maximum_bytes, 20) do
      service.generate(id: record.id, client: Source.new)
    end
    assert_equal 'failed', record.reload.state
    assert_equal 'export_quota', record.error_code
    refute record.artifact.attached?
  end

  def test_membership_revocation_after_prepare_prevents_generation
    record = prepare_export
    @member.destroy!
    service.generate(id: record.id, client: Source.new)
    assert_equal 'failed', record.reload.state
    assert_equal 'access_revoked', record.error_code
    refute record.artifact.attached?
  end

  def test_source_revocation_on_download_purges_previous_ready_file
    record = prepare_export
    source = Source.new
    service.generate(id: record.id, client: source)
    source.denied = 2
    assert_equal 'verifying', service.download(access: access, id: record.id).state
    service.verify(id: record.id, client: source)
    error = assert_raises(JrcServiceDesk::Glpi::Error) { service.download(access: access, id: record.id) }
    assert_equal 403, error.http_status
    assert_equal 'failed', record.reload.state
    refute record.artifact.attached?
  end

  def test_download_proof_is_single_use_and_source403_purges_artifact
    record = prepare_export
    source = Source.new
    service.generate(id: record.id, client: source)
    assert_equal 'verifying', service.download(access: access, id: record.id).state
    service.verify(id: record.id, client: source)
    assert record.reload.receipt.fetch(:can_download)
    assert record.verified_from <= record.verified_until
    JrcServiceDesk::Glpi::Client.stub(:new, source) do
      assert_equal record.id, service.download(access: access, id: record.id).id
    end
    refute record.reload.receipt.fetch(:can_download)
    assert_equal 'verifying', service.download(access: access, id: record.id).state
    service.verify(id: record.id, client: source)
    source.denied = 1
    JrcServiceDesk::Glpi::Client.stub(:new, source) do
      assert_raises(JrcServiceDesk::Glpi::Error) { service.download(access: access, id: record.id) }
    end
    refute record.reload.artifact.attached?
  end

  def test_disabled_unit_or_configuration_change_invalidates_download
    %i[unit configuration].each do |change|
      record = prepare_export
      service.generate(id: record.id, client: Source.new)
      change == :unit ? @unit.update!(active: false) : @connection.update!(timezone: 'America/Sao_Paulo')
      assert_raises(Pundit::NotAuthorizedError, JrcServiceDesk::Glpi::Error) do
        service.download(access: access, id: record.id)
      end
      refute record.reload.artifact.attached?
      @unit.update!(active: true) if change == :unit
    end
  end

  def test_foreign_account_cannot_inspect_or_cancel_receipt
    record = prepare_export
    original = record.account_id
    foreign = Account.create!(name: 'Foreign export', status: 'active')
    record.update_column(:account_id, foreign.id)
    assert_raises(ActiveRecord::RecordNotFound) { service.status(access: access, id: record.id) }
    assert_raises(ActiveRecord::RecordNotFound) { service.cancel(access: access, id: record.id) }
    record.update_column(:account_id, original)
  end

  def test_cancelled_and_expired_files_cannot_be_delivered
    cancelled = prepare_export
    service.cancel(access: access, id: cancelled.id)
    service.generate(id: cancelled.id, client: Source.new)
    assert_equal 'cancelled', cancelled.reload.state
    refute cancelled.artifact.attached?
    expired = prepare_export
    service.generate(id: expired.id, client: Source.new)
    expired.update!(expires_at: 1.second.ago)
    assert_raises(JrcServiceDesk::Glpi::Error) { service.download(access: access, id: expired.id) }
    assert_equal 'expired', expired.reload.state
    refute expired.artifact.attached?
  end

  def test_overview_filters_versioned_projection_and_labels_partial_coverage
    assert defined?(JrcServiceDesk::Glpi::Overview), 'Missing scoped GLPI overview'
    run = JrcServiceDesk::GlpiSyncRun.create!(account: @account, glpi_connection: @connection, account_user: @member,
      connection_version: @connection.lock_version, state: 'partial', finished_at: Time.current,
      coverage: { '0' => { state: 'partial', observed: 3, indexed: 2, error: 'ERROR_RIGHT_MISSING' } })
    [1, 2].each do |id|
      JrcServiceDesk::GlpiTicketSnapshot.create!(account: @account, glpi_connection: @connection, unit: @unit, glpi_sync_run: run,
        remote_id: id, entity_id: 0, connection_version: @connection.lock_version, observed_at: 2.minutes.ago,
        payload: { 'id' => id, 'entities_id' => 0, 'title' => 'Root', 'status' => id, 'priority' => 3, 'opened_at' => '2026-01-01' })
    end
    report = JrcServiceDesk::Glpi::Overview.new.call(access: access, filters: { 'status' => '1' })
    assert_equal 1, report.fetch(:total)
    assert_equal 'partial', report.fetch(:coverage).fetch(:state)
    assert_equal [0], report.fetch(:coverage).fetch(:scope_entity_ids)
    assert report.fetch(:observed_at)
    @connection.update!(timezone: 'America/Sao_Paulo')
    report = JrcServiceDesk::Glpi::Overview.new.call(access: access, filters: {})
    assert_equal 'unavailable', report.fetch(:coverage).fetch(:state)
    assert_nil report.fetch(:total)
  end
end
