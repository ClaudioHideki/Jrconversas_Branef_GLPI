# frozen_string_literal: true

# Contextual form metadata only. Inheritance never grants access to ancestor tickets.
class JrcServiceDesk::Glpi::MetadataScope
  TYPES = %w[ITILCategory TicketTemplate User].freeze
  attr_reader :entity_id

  def initialize(access:, client:, entity_id:)
    @access = JrcServiceDesk::Glpi::Execute.new.fresh_access(access)
    @client = client
    @entity_id = JrcServiceDesk::Glpi::Identifiers.remote(entity_id)
    @access.unit_for(@entity_id)
    @entities = {}
  end

  def authorize!(type, row)
    raise ArgumentError unless TYPES.include?(type)
    raise Pundit::NotAuthorizedError if [1, '1', true].include?(row['is_deleted'])
    return authorize_user!(row) if type == 'User'

    entity = JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('entities_id'))
    return row if entity == entity_id
    raise Pundit::NotAuthorizedError unless [1, '1', true].include?(row['is_recursive']) && ancestors.include?(entity)

    row
  end

  def recheck!
    @access = JrcServiceDesk::Glpi::Execute.new.fresh_access(@access)
    @access.unit_for(entity_id)
    self
  end

  def entity(id)
    @entities[id] ||= @client.get("Entity/#{id}").tap do |row|
      unless row.is_a?(Hash) && row['id'].to_s == id.to_s
        raise JrcServiceDesk::Glpi::Error.new('template_metadata_invalid')
      end
    end
  end

  def ancestors
    ids = []
    current = entity_id
    until current.zero?
      if ids.include?(current) || ids.length >= 100
        raise JrcServiceDesk::Glpi::Error.new('template_metadata_invalid')
      end
      ids << current
      parent = entity(current).fetch('entities_id')
      break if parent.nil?

      current = JrcServiceDesk::Glpi::Identifiers.remote(parent)
    end
    (ids + [current]).uniq
  end

  private

  def authorize_user!(row)
    id = JrcServiceDesk::Input.id(row.fetch('id'))
    raise Pundit::NotAuthorizedError if row.key?('is_active') && [0, '0', false].include?(row['is_active'])

    visible = @client.collection("User/#{id}/Profile_User/").any? do |link|
      raise Pundit::NotAuthorizedError unless link['users_id'].to_s == id.to_s

      entity = JrcServiceDesk::Glpi::Identifiers.remote(link.fetch('entities_id'))
      entity == entity_id || ([1, '1', true].include?(link['is_recursive']) && ancestors.include?(entity))
    end
    raise Pundit::NotAuthorizedError unless visible

    row
  end
end
