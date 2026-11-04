# frozen_string_literal: true

require_relative 'glpi_test_helper'

class GlpiSyncControlTest < GlpiIntegrationTest
  def test_prepare_persists_run_before_enqueuing_and_rejects_duplicate
    access = JrcServiceDesk::Glpi::Access.new(@identity)
    run = JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: access)
    assert run.persisted?
    assert_equal 'running', run.state
    assert_equal 'queued', run.coverage['phase']
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |entry| entry[:job] == JrcServiceDesk::GlpiSyncJob && entry[:args].last == run.id }
    refute_nil job
    error = assert_raises(JrcServiceDesk::Glpi::Error) { JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: access) }
    assert_equal 'sync_in_progress', error.code
  end

  def test_cancelled_queued_job_never_opens_a_remote_session
    access = JrcServiceDesk::Glpi::Access.new(@identity)
    run = JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: access)
    JrcServiceDesk::Glpi::SyncStatus.new.cancel(access: access, id: run.id)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Cancelled job contacted source' }) do
      JrcServiceDesk::GlpiSyncJob.perform_now(@connection.id, @member.id, run.id)
    end
    assert_equal 'failed', run.reload.state
    assert_equal 'sync_cancelled', run.coverage['error']
  end

  def test_configuration_change_before_job_is_rechecked_before_network
    run = JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: JrcServiceDesk::Glpi::Access.new(@identity))
    @connection.update!(categories: [{ id: 1, name: 'Changed', entity_id: 0 }])
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Stale configuration contacted source' }) do
      JrcServiceDesk::GlpiSyncJob.perform_now(@connection.id, @member.id, run.id)
    end
    assert_equal 'failed', run.reload.state
    assert_equal 'configuration_changed', run.coverage['error']
  end

  def test_role_revocation_before_job_is_rechecked_before_network
    run = JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: JrcServiceDesk::Glpi::Access.new(@identity))
    @member.update!(role: 'agent')
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Revoked actor contacted source' }) do
      JrcServiceDesk::GlpiSyncJob.perform_now(@connection.id, @member.id, run.id)
    end
    assert_equal 'failed', run.reload.state
    assert_equal 'access_revoked', run.coverage['error']
  end

  def test_agent_cannot_prepare_administrative_projection
    @member.update!(role: 'agent')
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: JrcServiceDesk::Glpi::Access.new(@identity))
    end
  end

  def test_enqueue_failure_leaves_a_failed_receipt
    access = JrcServiceDesk::Glpi::Access.new(@identity)
    JrcServiceDesk::GlpiSyncJob.stub(:perform_later, ->(*) { raise ActiveJob::EnqueueError, 'Synthetic failure' }) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: access) }
      assert_equal 'sync_enqueue_failed', error.code
    end
    assert_equal 'failed', JrcServiceDesk::GlpiSyncRun.where(glpi_connection: @connection).sole.state
  end

  def test_revocation_after_an_empty_entity_stops_before_the_next_source_request
    @connection.update!(entity_mappings: [{ entity_id: 0, unit_id: @unit.id }, { entity_id: 1, unit_id: @unit.id }])
    calls = 0
    client = Object.new
    member = @member
    client.define_singleton_method(:collection) do |*|
      calls += 1
      member.update!(role: 'agent')
      []
    end
    run = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: client)
    assert_equal 'failed', run.state
    assert_equal 'access_revoked', run.coverage['error']
    assert_equal 1, calls, 'Do not start another entity request after local authorization was revoked'
  end

  def test_cancellation_after_an_empty_entity_stops_before_the_next_source_request
    @connection.update!(entity_mappings: [{ entity_id: 0, unit_id: @unit.id }, { entity_id: 1, unit_id: @unit.id }])
    access = JrcServiceDesk::Glpi::Access.new(@identity)
    run = JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: access)
    calls = 0
    client = Object.new
    client.define_singleton_method(:collection) do |*|
      calls += 1
      JrcServiceDesk::Glpi::SyncStatus.new.cancel(access: access, id: run.id)
      []
    end
    result = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: client, run: run)
    assert_equal 'failed', result.state
    assert_equal 'sync_cancelled', result.coverage['error']
    assert_equal 1, calls, 'Do not start another entity request after cancellation'
  end
end
