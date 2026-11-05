# frozen_string_literal: true

class JrcServiceDesk::Glpi::TicketQuery
  FIELDS = %w[entity_id status priority search from to mine type page per_page].freeze
  attr_reader :access, :filters

  def initialize(access, parameters, deleted: false)
    @access = access.ready!
    raise Pundit::NotAuthorizedError if deleted && !access.context.administrator?

    @deleted = deleted
    @filters = JrcServiceDesk::Input.attributes(parameters, FIELDS)
  end

  def parameters(offset:, size:)
    entities = entity_ids
    criteria = [{ 'criteria' => entities.map { |id| condition(80, 'equals', id, 'OR') } }]
    unless access.all_tickets?
      criteria << { 'link' => 'AND', 'criteria' => [condition(4, 'equals', access.glpi_user_id), condition(5, 'equals', access.glpi_user_id, 'OR')] }
    end
    if mine?
      raise Pundit::NotAuthorizedError unless access.glpi_user_id

      criteria << condition(5, 'equals', access.glpi_user_id)
    end
    if filters['type'].present?
      type = JrcServiceDesk::Input.id(filters['type'])
      raise ArgumentError unless [1, 2].include?(type)

      criteria << condition(14, 'equals', type)
    end
    %w[status priority].each do |key|
      next if filters[key].blank?

      number = JrcServiceDesk::Input.id(filters[key])
      raise ArgumentError unless number.between?(1, 6)

      criteria << condition(key == 'status' ? 12 : 3, 'equals', number)
    end
    if filters['search'].present?
      raise ArgumentError unless filters['search'].is_a?(String) && filters['search'].length <= 200

      title = condition(1, 'contains', filters['search'])
      criteria << if search_ticket_id
                    { 'link' => 'AND', 'criteria' => [title, condition(2, 'equals', search_ticket_id, 'OR')] }
                  else
                    title
                  end
    end
    %w[from to].each do |key|
      next if filters[key].blank?

      value = filters[key]
      raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value)
      criteria << condition(15, key == 'from' ? 'morethan' : 'lessthan', "#{value} #{key == 'from' ? '00:00:00' : '23:59:59'}")
    end
    raise ArgumentError if filters['from'].present? && filters['to'].present? && filters['from'] > filters['to']

    { 'criteria' => criteria, 'forcedisplay' => JrcServiceDesk::Glpi::Normalize::FIELDS.keys, 'sort' => 2, 'order' => 'ASC',
      'range' => "#{offset}-#{offset + size - 1}", 'is_deleted' => @deleted ? 1 : 0 }
  end

  def page(client)
    page = JrcServiceDesk::Input.id(filters.fetch('page', 1))
    size = JrcServiceDesk::Input.id(filters.fetch('per_page', 25))
    raise ArgumentError unless page <= 100_000 && size <= 100

    result = client.get('search/Ticket/', parameters(offset: (page - 1) * size, size: size))
    { items: result_rows(result).map { |row| JrcServiceDesk::Glpi::Normalize.search(row).merge('is_deleted' => @deleted) },
      meta: { page: page, per_page: size, total: result.fetch('totalcount') } }
  end

  def all(client)
    each_batch(client).flat_map { |batch, _progress| batch }
  end

  # Yield bounded pages. IDs are retained only to detect unstable offset paging;
  # ticket payloads can be streamed without accumulating the full history.
  def each_batch(client)
    return enum_for(:each_batch, client) unless block_given?

    seen = {}
    offset = 0
    expected = nil
    loop do
      result = client.get('search/Ticket/', parameters(offset: offset, size: 200))
      raw_count = result.fetch('totalcount')
      raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless raw_count.to_s.match?(/\A(?:0|[1-9][0-9]*)\z/)

      count = Integer(raw_count)
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if expected && expected != count

      expected = count
      batch = result_rows(result)
      raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless batch.is_a?(Array) && batch.size <= 200

      batch.each do |row|
        id = JrcServiceDesk::Input.id(row.fetch('2'))
        raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if seen.key?(id)

        seen[id] = true
      end
      offset += batch.size
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if offset > count

      yield batch.map { |row| JrcServiceDesk::Glpi::Normalize.search(row) }, { total: count, processed: offset }
      break if offset >= count
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if batch.empty?
    end
    raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless seen.size == expected
  end

  def entity_ids
    entities = access.entity_ids
    return entities if filters['entity_id'].blank?

    entity = JrcServiceDesk::Glpi::Identifiers.remote(filters['entity_id'])
    raise Pundit::NotAuthorizedError unless entities.include?(entity)

    [entity]
  end

  def mine?
    value = filters['mine']
    return false if value.nil? || value == false || value == 'false'
    return true if value == true || value == 'true'

    raise ArgumentError
  end

  def search_ticket_id
    value = filters['search']
    return nil unless value.is_a?(String) && value.match?(/\A[1-9][0-9]{0,18}\z/)

    JrcServiceDesk::Input.id(value)
  rescue ArgumentError
    nil
  end

  private

  def result_rows(result)
    result.fetch('data') do
      raise KeyError, 'Missing GLPI data for nonempty result' unless [0, '0'].include?(result.fetch('totalcount'))

      []
    end
  end

  def condition(field, searchtype, value, link = 'AND')
    { 'field' => field, 'searchtype' => searchtype, 'value' => value, 'link' => link }
  end
end
