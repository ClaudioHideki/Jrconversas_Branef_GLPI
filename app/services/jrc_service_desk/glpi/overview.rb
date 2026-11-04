# frozen_string_literal: true

class JrcServiceDesk::Glpi::Overview
  Selection = Struct.new(:access, :query, :scope, :coverage, :observed_at, keyword_init: true)

  def call(access:, filters:)
    data = selection(access: access, filters: filters)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::GlpiPolicy.new(data.access.context.to_h, :glpi).report?
    rows = Enumerator.new do |stream|
      data.scope.find_each { |snapshot| stream << snapshot.payload.merge('entity' => snapshot.entity_id) }
    end
    report = JrcServiceDesk::Glpi::Report.build(rows)
    report[:total] = nil if data.coverage[:state] == 'unavailable'
    report.merge(coverage: data.coverage, observed_at: data.observed_at)
  end

  def list(access:, filters:)
    data = selection(access: access, filters: filters)
    page = JrcServiceDesk::Input.id(data.query.filters.fetch('page', 1))
    size = JrcServiceDesk::Input.id(data.query.filters.fetch('per_page', 25))
    raise ArgumentError unless page <= 100_000 && size <= 100

    items = data.scope.order(:remote_id).offset((page - 1) * size).limit(size).map do |snapshot|
      snapshot.payload.merge('source' => 'glpi', 'id' => snapshot.remote_id, 'entities_id' => snapshot.entity_id,
                             'observed_at' => snapshot.observed_at.iso8601)
    end
    { items: items, meta: { page: page, per_page: size, total: data.coverage[:state] == 'unavailable' ? nil : data.scope.count },
      coverage: data.coverage, observed_at: data.observed_at, generated_at: Time.current.iso8601 }
  end

  # One scope builder for the list, indicators and background exports. It never
  # infers an entity from its display name or silently falls back to native data.
  def selection(access:, filters:)
    access = JrcServiceDesk::Glpi::Access.new(access.context.to_h).ready!
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::GlpiPolicy.new(access.context.to_h, :glpi).read?

    query = JrcServiceDesk::Glpi::TicketQuery.new(access, filters)
    query.parameters(offset: 0, size: 1) # Shared strict validation, including actor identity.
    run = JrcServiceDesk::GlpiSyncRun.where(account_id: access.context.account.id, glpi_connection: access.connection,
      connection_version: access.connection.lock_version).order(id: :desc).first
    scope = JrcServiceDesk::GlpiTicketSnapshot.current_for(access.connection)
      .where(entity_id: query.entity_ids, unit_id: access.context.unit_scope.select(:id), glpi_sync_run_id: run&.id)
    scope = scope.none unless run
    coverage = coverage_for(access, query, run, scope)
    scope = filtered(scope, query)
    observed_at = scope.minimum(:observed_at)&.iso8601
    Selection.new(access: access, query: query, scope: scope, coverage: coverage, observed_at: observed_at)
  end

  private

  def coverage_for(access, query, run, scope)
    entries = query.entity_ids.to_h { |entity| [entity.to_s, run&.coverage&.fetch(entity.to_s, nil)] }
    complete = run && %w[complete partial].include?(run.state) && entries.values.all? { |entry| entry && entry['state'] == 'complete' }
    indexed = scope.group(:entity_id).count
    complete &&= entries.all? { |id, entry| indexed.fetch(id.to_i, 0) == entry['indexed'].to_i }
    restricted = !access.all_tickets? || query.mine?
    if restricted
      # A shared synchronization run may include other actors in the same unit.
      # Its totals, nested errors and actor metadata are not a permitted report.
      indexed = filtered(scope, query).group(:entity_id).count
      entries = entries.to_h do |id, entry|
        count = indexed.fetch(id.to_i, 0)
        [id, { 'state' => entry&.fetch('state', 'partial') || 'unavailable', 'observed' => count, 'indexed' => count }]
      end
    end
    { state: run.nil? ? 'unavailable' : complete ? 'complete' : 'partial', source: 'glpi_projection',
      connection_version: access.connection.lock_version, scope_entity_ids: query.entity_ids, run_id: run&.id&.to_s,
      observed: entries.values.compact.sum { |entry| entry['observed'].to_i }, indexed: indexed.values.sum,
      errors: restricted ? {} : entries.filter_map { |id, entry| [id, entry ? entry['error'] : 'coverage_missing'] if !entry || entry['error'] }.to_h,
      count_scope: restricted ? 'authorized_filtered_projection' : 'authorized_entities',
      entities: entries, collected_at: run&.finished_at&.iso8601 }
  end

  def filtered(scope, query)
    filters = query.filters
    %w[status priority type].each do |key|
      scope = scope.where("payload->>? = ?", key, filters[key].to_s) if filters[key].present?
    end
    if filters['search'].present?
      scope = scope.where("payload->>'title' ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(filters['search'])}%")
    end
    scope = scope.where("LEFT(payload->>'opened_at', 10) >= ?", filters['from']) if filters['from'].present?
    scope = scope.where("LEFT(payload->>'opened_at', 10) <= ?", filters['to']) if filters['to'].present?
    if query.mine? || !query.access.all_tickets?
      unless scope.where("COALESCE(payload->>'actor_scope_available', 'false') != 'true'").none?
        raise JrcServiceDesk::Glpi::Error.new('projection_filter_unavailable', 422)
      end

      field = query.mine? ? 'assigned_user_ids' : 'actor_user_ids'
      scope = scope.where("payload->? @> ?::jsonb", field, [query.access.glpi_user_id].to_json)
    end
    scope
  end
end
