# frozen_string_literal: true

# GLPI-only projection. No remote mutation and no message delivery.
class JrcServiceDesk::Glpi::HistoricalSentiment
  LIMIT = 100
  CHARACTERS = 1000

  def initialize(access:, from:, to:)
    @access = access.ready!
    raise Pundit::NotAuthorizedError unless access.context.capability?(:dashboard_view)
    raise ArgumentError unless from.is_a?(String) && to.is_a?(String)

    @zone = Time.find_zone!(access.connection.timezone)
    @from = @zone.local(*Date.iso8601(from).to_s.split('-').map(&:to_i))
    requested_to = @zone.local(*Date.iso8601(to).to_s.split('-').map(&:to_i))
    raise ArgumentError unless @from < requested_to && requested_to <= @from + 62.days

    @to = [requested_to, Time.current.in_time_zone(@zone).change(usec: 0)].min
    raise ArgumentError unless @from < @to

    @requested_to = requested_to
  end

  # Enumerates candidates, including tickets opened before the requested period.
  # Only authorized IDs are returned; the actual public interactions are selected
  # again by analyze, so a date_mod change alone is not classified as a response.
  def candidates(client:)
    query = JrcServiceDesk::Glpi::ResourceQuery.new
    session = client.get('getFullSession/').fetch('session')
    visible = session.fetch('glpiactiveentities')
    visible = visible.values if visible.is_a?(Hash)
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless visible.is_a?(Array)

    visible = visible.map { |id| JrcServiceDesk::Glpi::Identifiers.remote(id) }
    missing = @access.entity_ids - visible
    raise JrcServiceDesk::Glpi::Error.new('source_scope_incomplete', 422) if missing.any?

    ids = []
    candidate_ids(client).each do |id|
      begin
        ticket = query.raw(access: @access, client: client, kind: 'tickets', id: id)
        next if [1, '1', true].include?(ticket['is_deleted'])
        next unless timestamp(ticket.fetch('date')) < @to && timestamp(ticket.fetch('date_mod')) >= @from

        ids << JrcServiceDesk::Input.id(ticket.fetch('id'))
      rescue Pundit::NotAuthorizedError
        next
      end
    end
    { ticket_ids: ids.uniq.sort, period: period, candidate_count: ids.uniq.size, source_entity_ids: @access.entity_ids,
      scope: 'Candidates require public text in the period before analysis; date_mod alone is not an interaction.' }
  end

  # The interactive list uses the existing, scoped source projection. A recent
  # modification identifies a candidate, not proof of public text in the period.
  def candidate_page(filters:)
    data = JrcServiceDesk::Glpi::Overview.new.selection(access: @access, filters: filters)
    page = JrcServiceDesk::Input.id(data.query.filters.fetch('page', 1))
    size = JrcServiceDesk::Input.id(data.query.filters.fetch('per_page', 25))
    raise ArgumentError unless page <= 100_000 && size <= 100

    scope = data.scope.where("payload->>'date' < ?", @to.strftime('%Y-%m-%d %H:%M:%S'))
      .where("payload->>'date_mod' >= ?", @from.strftime('%Y-%m-%d %H:%M:%S'))
    items = scope.order(:remote_id).offset((page - 1) * size).limit(size).map do |snapshot|
      snapshot.payload.merge('source' => 'glpi', 'id' => snapshot.remote_id, 'entities_id' => snapshot.entity_id,
                             'observed_at' => snapshot.observed_at.iso8601)
    end
    { items: items, meta: { page: page, per_page: size, total: data.coverage[:state] == 'unavailable' ? nil : scope.count },
      coverage: data.coverage, observed_at: data.observed_at, period: period,
      scope: 'Candidates require public text in the period before analysis; date_mod alone is not an interaction.' }
  end

  def analyze(client:, ticket_id:)
    query = JrcServiceDesk::Glpi::ResourceQuery.new
    ticket = query.raw(access: @access, client: client, kind: 'tickets', id: ticket_id)
    raise Pundit::NotAuthorizedError if [1, '1', true].include?(ticket['is_deleted'])

    actors = query.related(access: @access, client: client, kind: 'actors', ticket_id: ticket.fetch('id')).fetch(:items)
    @technical_user = client.get('getFullSession/').fetch('session').fetch('glpiID').to_s
    records = [{ 'id' => ticket.fetch('id'), 'content' => ticket['content'], 'date' => ticket.fetch('date'),
                 'users_id' => ticket['users_id_recipient'], 'source_type' => 'Ticket' }]
    { 'followups' => 'ITILFollowup', 'solutions' => 'ITILSolution' }.each do |kind, type|
      rows = query.related(access: @access, client: client, kind: kind, ticket_id: ticket.fetch('id')).fetch(:items)
      records.concat(rows.map { |row| row.merge('source_type' => type) })
    end
    selected = records.select { |row| public_record?(row) }.filter_map do |row|
      date = timestamp(row.fetch('date_creation', row['date']))
      next unless date >= @from && date < @to

      text = JrcServiceDesk::Glpi::Normalize.text(row['content']).strip
      next if text.empty?

      { id: "#{row.fetch('source_type')}/#{JrcServiceDesk::Input.id(row.fetch('id'))}",
        role: role(row['users_id'], actors), content: text.first(CHARACTERS),
        occurred_at: date.iso8601, truncated: text.length > CHARACTERS }
    end.sort_by { |row| [row[:occurred_at], row[:id]] }
    return { ticket_id: ticket.fetch('id'), status: 'no_public_text', period: period } if selected.empty?

    analyze_selected(ticket, selected, client: client)
  end

  private

  def candidate_ids(client)
    options = client.get('listSearchOptions/Ticket/')
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless options.is_a?(Hash)
    fields = { 'id' => ['glpi_tickets', 'id'], 'opened' => ['glpi_tickets', 'date'],
               'modified' => ['glpi_tickets', 'date_mod'], 'entity' => ['glpi_entities', 'completename'] }.transform_values do |table, field|
      found = options.find { |key, row| key.to_s.match?(/\A[1-9]\d*\z/) && row.is_a?(Hash) && row['table'] == table && row['field'] == field }
      raise JrcServiceDesk::Glpi::Error.new('search_schema_unsupported', 422) unless found

      JrcServiceDesk::Input.id(found.first)
    end
    # Collection validates GLPI 10's native ID column; never guess another ID.
    raise JrcServiceDesk::Glpi::Error.new('search_schema_unsupported', 422) unless fields.fetch('id') == 2

    criteria = [{ 'criteria' => @access.entity_ids.map { |id| condition(fields.fetch('entity'), 'equals', id, 'OR') } },
                condition(fields.fetch('opened'), 'lessthan', @to.strftime('%Y-%m-%d %H:%M:%S')),
                condition(fields.fetch('modified'), 'morethan', (@from - 1.second).strftime('%Y-%m-%d %H:%M:%S'))]
    parameters = { 'criteria' => criteria, 'forcedisplay' => [fields.fetch('id')], 'is_deleted' => 0,
                   'sort' => fields.fetch('id'), 'order' => 'DESC', 'range' => '0-0' }
    first = client.get('search/Ticket/', parameters)
    rows = first.fetch('data') do
      raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless [0, '0'].include?(first.fetch('totalcount'))

      []
    end
    rows = rows.values if rows.is_a?(Hash)
    unless rows.is_a?(Array) && rows.size <= 1 && first.fetch('totalcount').to_s.match?(/\A\d+\z/)
      raise JrcServiceDesk::Glpi::Error.new('invalid_response')
    end
    if rows.empty? && first.fetch('totalcount').to_i.positive?
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409)
    end
    return [] if rows.empty?

    high_water = JrcServiceDesk::Input.id(rows.first.fetch(fields.fetch('id').to_s))
    # GLPI 10 numeric fields encode comparisons in the value. A numeric
    # `lessthan` search type alone is treated as equality by that version.
    criteria << condition(fields.fetch('id'), 'contains', "<=#{high_water}")
    # Enumerate IDs quickly before individual authorization/detail reads. New
    # tickets cannot shift this window; Collection still rejects source drift.
    ids = client.collection('search/Ticket/', parameters.except('range').merge('order' => 'ASC'), batch_size: 1000)
                .map { |row| JrcServiceDesk::Input.id(row.fetch(fields.fetch('id').to_s)) }
    raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless ids.include?(high_water)

    ids
  end

  def condition(field, searchtype, value, link = 'AND')
    { 'field' => field, 'searchtype' => searchtype, 'value' => value, 'link' => link }
  end

  def analyze_selected(ticket, selected, client:)
    rows = selected.last(LIMIT)
    messages = rows.map { |row| row.slice(:id, :role, :content) }
    payload = { account_id: @access.context.account.id, request_id: SecureRandom.uuid,
                source: { system: 'glpi', resource_type: 'Ticket', resource_id: ticket.fetch('id').to_s }, messages: messages }
    # Permissions are checked again after source collection and before inference.
    fresh = JrcServiceDesk::Glpi::Access.new(@access.context.to_h).ready!
    raise Pundit::NotAuthorizedError unless fresh.context.capability?(:dashboard_view)
    unless fresh.connection.id == @access.connection.id && fresh.connection.lock_version == @access.connection.lock_version
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end

    fresh.authorize_ticket!(client, ticket)
    result = JrcNico::OperationalInference.metered(account: fresh.context.account, user: fresh.context.user, kind: 'sentiment',
                                                 reservation_tokens: payload.to_json.bytesize + 16_000,
                                                 request_id: payload[:request_id]) do |provider, ledger|
      JrcNico::RuntimeClient.new(provider: provider, ledger: ledger).sentiment(payload)
    end
    report = result.fetch('report')
    references = messages.pluck(:id)
    evidence = report['evidence']
    unless evidence.is_a?(Array) && evidence.all? { |item| item.is_a?(Hash) && references.include?(item['message_id']) }
      raise JrcNico::RuntimeClient::Error, 'invalid_response'
    end

    { ticket_id: ticket.fetch('id'), status: 'analyzed', inferred: true, period: period,
      source_version: ticket.fetch('date_mod'), analyzed_at: Time.current.iso8601, model: result.fetch('model'), report: report,
      usage: result.fetch('usage'),
      source_window: { references: references, digest: Digest::SHA256.hexdigest(messages.to_json),
                       text_records_in_period: selected.size, analyzed_records: rows.size, omitted_records: selected.size - rows.size,
                       truncated_records: rows.count { |row| row[:truncated] }, characters_per_record: CHARACTERS,
                       first_at: rows.first[:occurred_at], last_at: rows.last[:occurred_at] },
      limitations: 'Inferred sentiment, not a customer satisfaction survey. Public text only; no attachments, audio or private notes.' }
  end

  def timestamp(value)
    raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\z/)

    @zone.strptime(value.tr('T', ' '), '%Y-%m-%d %H:%M:%S')
  end

  def role(user_id, actors)
    return 'unknown' if user_id.to_s == @technical_user

    types = actors.select { |actor| user_id.to_i.positive? && actor['users_id'].to_s == user_id.to_s }.map { |actor| actor['type'].to_i }.uniq
    return 'customer' if types == [1]
    return 'operator' if types == [2]

    'unknown'
  end

  def public_record?(row)
    return [0, '0', false].include?(row['is_private']) if row['source_type'] == 'ITILFollowup'

    ![1, '1', true].include?(row['is_private'])
  end

  def period
    { from: @from.iso8601, to_exclusive: @to.iso8601, requested_to_exclusive: @requested_to.iso8601,
      timezone: @zone.tzinfo.name, partial: @to < @requested_to }
  end
end
