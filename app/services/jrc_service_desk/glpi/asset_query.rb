# frozen_string_literal: true

# Read-only inventory consultation for an already authorized service ticket.
# Item_Ticket association IDs remain separate from these typed asset targets.
class JrcServiceDesk::Glpi::AssetQuery
  FIELDS = %w[id name comment entities_id serial otherserial contact contact_num locations_id manufacturers_id date_mod].freeze

  def call(access:, client:, filters:)
    values = JrcServiceDesk::Input.attributes(filters, %w[ticket_id asset_type page per_page search])
    access, parent, type = context!(access, client, values)
    page = JrcServiceDesk::Input.id(values.fetch('page', 1))
    size = JrcServiceDesk::Input.id(values.fetch('per_page', 25))
    search = values.fetch('search', '')
    raise ArgumentError unless size <= 100 && page <= 100_000 && search.is_a?(String) && search.length <= 200

    items = []
    found = 0
    client.collection("#{type}/", 'sort' => 'id', 'order' => 'ASC').each do |row|
      next unless visible?(access, parent, row)

      item = normalize(type, row)
      next if search.present? && !%w[name serial otherserial comment].any? { |field| item[field].to_s.downcase.include?(search.downcase) }

      items << item if found >= (page - 1) * size && items.size < size
      found += 1
    end
    context!(access, client, values)
    { items: items, meta: { page: page, per_page: size, total: found },
      coverage: { complete: true, errors: {}, source: 'glpi', observed_at: Time.current.iso8601, atomic_snapshot: false } }
  end

  def find(access:, client:, id:, filters:)
    values = JrcServiceDesk::Input.attributes(filters, %w[ticket_id asset_type])
    access, parent, type = context!(access, client, values)
    id = JrcServiceDesk::Input.id(id)
    row = client.get("#{type}/#{id}")
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless row.is_a?(Hash) && row['id'].to_s == id.to_s
    raise Pundit::NotAuthorizedError unless visible?(access, parent, row)

    context!(access, client, values)
    normalize(type, row)
  end

  private

  def context!(access, client, values)
    type = values.fetch('asset_type')
    raise ArgumentError unless JrcServiceDesk::Glpi::ResourceQuery::ASSET_TYPES.include?(type)

    access = JrcServiceDesk::Glpi::Execute.new.fresh_access(access)
    parent = JrcServiceDesk::Glpi::ResourceQuery.new.raw(access: access, client: client, kind: 'tickets', id: values.fetch('ticket_id'))
    raise Pundit::NotAuthorizedError if [1, '1', true].include?(parent['is_deleted'])

    [access, parent, type]
  end

  def visible?(access, parent, row)
    entity = JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('entities_id'))
    return false if [1, '1', true].include?(row['is_deleted']) || entity != JrcServiceDesk::Glpi::Identifiers.remote(parent.fetch('entities_id'))

    access.unit_for(entity)
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def normalize(type, row)
    row.slice(*FIELDS).transform_values { |value| value.is_a?(String) ? JrcServiceDesk::Glpi::Normalize.text(value) : value }
      .merge('itemtype' => type)
  end
end
