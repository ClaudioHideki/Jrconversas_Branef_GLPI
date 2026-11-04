# frozen_string_literal: true

class JrcServiceDesk::Glpi::SyncStatus
  def prepare(access:)
    access = authorize!(access).ready!
    run = JrcServiceDesk::GlpiSyncRun.create!(account: access.context.account, glpi_connection: access.connection,
      account_user: access.context.account_user, connection_version: access.connection.lock_version, coverage: { 'phase' => 'queued' })
    begin
      job = JrcServiceDesk::GlpiSyncJob.perform_later(access.connection.id, access.context.account_user.id, run.id)
      raise ActiveJob::EnqueueError, 'Queue did not accept job' unless job && job.successfully_enqueued?
    rescue StandardError => e
      run.update!(state: 'failed', finished_at: Time.current, coverage: { 'phase' => 'failed', 'error' => 'sync_enqueue_failed' })
      Rails.logger.error("GLPI sync enqueue failed: #{e.class}")
      raise JrcServiceDesk::Glpi::Error.new('sync_enqueue_failed', 503), cause: nil
    end
    run.reload
  rescue ActiveRecord::RecordNotUnique
    raise JrcServiceDesk::Glpi::Error.new('sync_in_progress', 409), cause: nil
  end

  def status(access:, id:)
    scope(authorize!(access)).find(JrcServiceDesk::Input.id(id))
  end

  def latest(access:)
    scope(authorize!(access)).order(created_at: :desc, id: :desc).first
  end

  def cancel(access:, id:)
    run = status(access: access, id: id)
    run.with_lock do
      if run.state == 'running'
        run.update!(state: 'failed', finished_at: Time.current,
                    coverage: run.coverage.merge('phase' => 'cancelled', 'error' => 'sync_cancelled'))
      end
    end
    run
  end

  private

  def authorize!(access)
    fresh = JrcServiceDesk::Glpi::Access.new(access.context.to_h)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::GlpiPolicy.new(fresh.context.to_h, :glpi).manage?

    fresh
  end

  def scope(access)
    JrcServiceDesk::GlpiSyncRun.where(account_id: access.context.account.id, glpi_connection: access.connection)
  end
end
