# frozen_string_literal: true

class JrcServiceDesk::Glpi::SentimentBatch
  Batch = JrcServiceDesk::GlpiSentimentBatch
  LEASE = 10.minutes

  def prepare(access:, values:)
    authorize!(access)
    filters = values
    started_at = Time.current
    window = filters.slice('from', 'to')
    query = filters.except('from', 'to')
    data = if window.empty?
             JrcServiceDesk::Glpi::Overview.new.selection(access: access, filters: query)
           else
             JrcServiceDesk::Glpi::HistoricalSentiment.new(access: access, observed_until: started_at, **window.symbolize_keys)
                                                       .candidate_selection(filters: query)
           end
    if data.coverage.fetch(:state) != 'complete'
      raise JrcServiceDesk::Glpi::Error.new('sentiment_coverage_incomplete', 422)
    end
    tickets = data.scope.distinct.order(:remote_id).pluck(:remote_id, :entity_id)
    raise ArgumentError if tickets.empty?

    batch = Batch.transaction do
      record = Batch.create!(account: access.context.account, account_user: access.context.account_user, glpi_connection: access.connection,
                             connection_version: access.connection.lock_version, entity_ids: tickets.map(&:last).uniq,
                             filters: filters, coverage: data.coverage, total: tickets.size, created_at: started_at)
      tickets.each_slice(1000) do |rows|
        record.items.insert_all!(rows.map { |remote_id, entity_id| { remote_id: remote_id, entity_id: entity_id } })
      end
      record
    end
    JrcServiceDesk::GlpiSentimentBatchJob.perform_later(batch.id)
    batch
  rescue ActiveRecord::RecordNotUnique
    raise JrcServiceDesk::Glpi::Error.new('sentiment_batch_active', 409)
  end

  def latest(access:)
    authorize!(access)
    batch = owned(access).where(connection_version: access.connection.lock_version).order(id: :desc).first
    authorize!(access, batch) if batch
    batch
  end

  def find(access:, id:)
    authorize!(access)
    batch = owned(access).find(JrcServiceDesk::Input.id(id))
    authorize!(access, batch)
    batch
  end

  def cancel(batch:)
    batch.with_lock do
      if %w[queued running].include?(batch.state)
        batch.items.where(state: 'queued').update_all(state: 'cancelled', updated_at: Time.current)
        batch.update!(state: batch.items.exists?(state: 'running') ? 'cancelling' : 'cancelled')
      end
    end
    batch
  end

  # The consolidated view uses the current authorized projection and excludes
  # free text. Full analysis is disclosed only after a live GLPI read.
  def rows(batch:, access:, page:)
    page = JrcServiceDesk::Input.id(page)
    raise ArgumentError unless page <= 100_000

    snapshots = JrcServiceDesk::GlpiTicketSnapshot.current_for(access.connection)
                   .where(entity_id: access.entity_ids, unit_id: access.context.unit_scope.select(:id))
    scope = batch.items.where(
      snapshots.where('remote_id = jrc_service_desk_glpi_sentiment_items.remote_id AND entity_id = jrc_service_desk_glpi_sentiment_items.entity_id')
               .arel.exists
    )
    items = scope.order(:remote_id).offset((page - 1) * 100).limit(100).to_a
    titles = snapshots.where(remote_id: items.map(&:remote_id)).pluck(:remote_id, Arel.sql("payload->>'title'")).to_h
    { items: items.map { |item| summary(item, titles[item.remote_id]) }, page: page, total: scope.count, per_page: 100 }
  end

  def detail(batch:, access:, id:)
    item = batch.items.find_by!(remote_id: JrcServiceDesk::Input.id(id), state: 'analyzed')
    JrcServiceDesk::Glpi::Client.new(access.connection).session(read_only: true) do |client|
      source = JrcServiceDesk::Glpi::ResourceQuery.new.raw(access: access, client: client, kind: 'tickets', id: item.remote_id)
      if source['entities_id'].to_s != item.entity_id.to_s || [1, '1', true].include?(source['is_deleted'])
        raise Pundit::NotAuthorizedError
      end
      unless source['date_mod'] == item.result.fetch('source_version')
        raise JrcServiceDesk::Glpi::Error.new('source_changed', 409)
      end

      authorize!(access, batch)
      item.result.merge('title' => JrcServiceDesk::Glpi::Normalize.text(source['name']))
    end
  end

  def step(batch)
    item = claim(batch)
    return unless item

    access = worker_access(batch)
    window = batch.filters.slice('from', 'to').symbolize_keys
    window = { scope: 'ticket' } if window.empty?
    analysis = JrcServiceDesk::Glpi::HistoricalSentiment.new(access: access, observed_until: batch.created_at, **window)
    result = JrcServiceDesk::Glpi::Client.new(access.connection).session(read_only: true) do |client|
      analysis.analyze(client: client, ticket_id: item.remote_id, expected_entity: item.entity_id) do
        unless item.reload.state == 'running' && LEASE.ago < item.updated_at
          raise JrcServiceDesk::Glpi::Error.new('interrupted', 409)
        end
      end
    end
    worker_access(batch)
    finish_item(item, state: result.fetch(:status), result: result)
  rescue JrcNico::RunCapacity::Exceeded => error
    if error.code == 'concurrency_limit'
      finish_item(item, state: 'queued')
      return 30.seconds
    end

    stop_with_error(batch, item, error.code)
  rescue JrcServiceDesk::Glpi::Error, JrcNico::RuntimeClient::Error => error
    if %w[not_configured configuration_changed provider_authentication_failed provider_unauthorized provider_forbidden].include?(error.code)
      stop_with_error(batch, item, error.code)
    else
      finish_item(item, state: 'failed', error: error.code)
      return 1.minute if error.code == 'provider_rate_limited'
    end
  rescue Pundit::NotAuthorizedError
    # Losing the ticket is different from losing the right to run the batch.
    finish_item(item, state: 'failed', error: 'access_revoked')
    begin
      worker_access(batch)
    rescue Pundit::NotAuthorizedError, JrcServiceDesk::Glpi::Error
      stop_with_error(batch, item, 'access_revoked')
    end
  rescue StandardError => error
    raise unless item

    finish_item(item, state: 'failed', error: 'unavailable')
    Rails.logger.warn("GLPI sentiment batch #{batch.id} item #{item.id}: #{error.class.name}")
  end

  private

  def owned(access)
    Batch.where(account_id: access.context.account.id, account_user_id: access.context.account_user.id, glpi_connection: access.connection)
  end

  def authorize!(access, batch = nil)
    access.ready!
    policy = JrcServiceDesk::GlpiPolicy.new(access.context.to_h, :glpi)
    raise Pundit::NotAuthorizedError unless policy.report? && access.all_tickets?
    return access unless batch

    raise Pundit::NotAuthorizedError unless (batch.entity_ids - access.entity_ids).empty?
    unless access.connection.id == batch.glpi_connection_id && access.connection.lock_version == batch.connection_version
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end

    access
  end

  def worker_access(batch)
    member = AccountUser.find_by(id: batch.account_user_id, account_id: batch.account_id)
    raise Pundit::NotAuthorizedError unless member

    authorize!(JrcServiceDesk::Glpi::Access.new(account: batch.account, user: member.user, account_user: member), batch)
  end

  def claim(batch)
    batch.with_lock do
      return unless Batch::ACTIVE_STATES.include?(batch.state)

      batch.items.where(state: 'running', updated_at: ...LEASE.ago)
           .update_all(state: 'failed', error: 'interrupted', updated_at: Time.current)
      return if batch.items.exists?(state: 'running')

      if batch.state == 'cancelling'
        batch.update!(state: 'cancelled')
        return
      end
      item = batch.items.where(state: 'queued').order(:id).first
      if item
        item.update!(state: 'running')
        batch.update!(state: 'running')
      else
        batch.update!(state: 'complete')
      end
      item
    end
  end

  def finish_item(item, **attributes)
    item.batch.with_lock do
      next unless item.reload.state == 'running'

      attributes = { state: 'cancelled' } if item.batch.state == 'cancelling' && attributes[:state] == 'queued'
      item.update!(attributes)
      item.batch.update!(state: 'cancelled') if item.batch.state == 'cancelling'
    end
  end

  def stop_with_error(batch, item, code)
    finish_item(item, state: 'failed', error: code)
    batch.with_lock do
      next unless Batch::ACTIVE_STATES.include?(batch.state)

      batch.items.where(state: 'queued').update_all(state: 'cancelled', updated_at: Time.current)
      batch.update!(state: 'failed', error: code)
    end
  end

  def summary(item, title)
    result = (item.result || {}).slice('period', 'model', 'usage', 'analyzed_at')
    if item.result&.key?('report')
      result['report'] = item.result.fetch('report').slice('customer_sentiment', 'agent_sentiment', 'quality_score')
      result['source_window'] = item.result.fetch('source_window').slice('analyzed_records', 'omitted_records', 'truncated_records')
    end
    result.merge(ticket_id: item.remote_id, title: title, status: item.state, error: item.error)
  end
end
