# frozen_string_literal: true

class JrcServiceDesk::Glpi::TicketQuery
  FIELDS = %w[entity_id status priority search from to page per_page].freeze
  attr_reader :access, :filters

  def initialize(access, parameters)
    @access = access.ready!
    @filters = JrcServiceDesk::Input.attributes(parameters, FIELDS)
  end

  def parameters(offset:, size:)
    entities = access.entity_ids
    if filters['entity_id'].present?
      entity = JrcServiceDesk::Glpi::Identifiers.remote(filters['entity_id'])
      raise Pundit::NotAuthorizedError unless entities.include?(entity)

      entities = [entity]
    end
    criteria = [{ 'criteria' => entities.map { |id| condition(80, 'equals', id, 'OR') } }]
    unless access.all_tickets?
      criteria << { 'link' => 'AND', 'criteria' => [condition(4, 'equals', access.glpi_user_id), condition(5, 'equals', access.glpi_user_id, 'OR')] }
    end
    %w[status priority].each do |key|
      next if filters[key].blank?

      number = JrcServiceDesk::Input.id(filters[key])
      raise ArgumentError unless number.between?(1, 6)

      criteria << condition(key == 'status' ? 12 : 3, 'equals', number)
    end
    if filters['search'].present?
      raise ArgumentError unless filters['search'].is_a?(String) && filters['search'].length <= 200

      criteria << condition(1, 'contains', filters['search'])
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
      'range' => "#{offset}-#{offset + size - 1}", 'is_deleted' => 0 }
  end

  def page(client)
    page = JrcServiceDesk::Input.id(filters.fetch('page', 1))
    size = JrcServiceDesk::Input.id(filters.fetch('per_page', 25))
    raise ArgumentError unless page <= 100_000 && size <= 100

    result = client.get('search/Ticket/', parameters(offset: (page - 1) * size, size: size))
    { items: result.fetch('data').map { |row| JrcServiceDesk::Glpi::Normalize.search(row) },
      meta: { page: page, per_page: size, total: result.fetch('totalcount') } }
  end

  def all(client)
    rows = {}
    offset = 0
    expected = nil
    loop do
      result = client.get('search/Ticket/', parameters(offset: offset, size: 200))
      count = result.fetch('totalcount').to_i
      raise JrcServiceDesk::Glpi::Error.new('report_limit', 422) if count > 10_000
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if expected && expected != count

      expected = count
      batch = result.fetch('data')
      batch.each do |row|
        id = JrcServiceDesk::Input.id(row.fetch('2'))
        raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if rows.key?(id)

        rows[id] = JrcServiceDesk::Glpi::Normalize.search(row)
      end
      offset += batch.size
      break if offset >= count
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if batch.empty?
    end
    raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) unless rows.size == expected

    rows.values
  end

  private

  def condition(field, searchtype, value, link = 'AND')
    { 'field' => field, 'searchtype' => searchtype, 'value' => value, 'link' => link }
  end
end
