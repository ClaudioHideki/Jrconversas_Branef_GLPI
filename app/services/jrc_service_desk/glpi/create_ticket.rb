# frozen_string_literal: true

require 'cgi'

class JrcServiceDesk::Glpi::CreateTicket
  FIELDS = %w[entity_id title description type urgency impact category_id requester_id idempotency_key].freeze

  def initialize(access)
    @access = access.ready!
  end

  def call(attributes)
    raise Pundit::NotAuthorizedError unless access.context.capability?(:tickets_create)

    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    entity = JrcServiceDesk::Glpi::Identifiers.remote(values.fetch('entity_id'))
    access.unit_for(entity)
    input = normalized_input(values, entity)
    key = JrcServiceDesk::Input.request_key(values.fetch('idempotency_key'))
    fingerprint = JrcServiceDesk::CanonicalJson.digest(input.merge('connection_version' => access.connection.lock_version))
    JrcServiceDesk::Glpi::Execute.new.call(access: access, operation: 'ticket.create', target_id: nil, entity_id: entity,
      attributes: input, idempotency_key: key, legacy_fingerprint: fingerprint, prepared: true)
  end

  private

  attr_reader :access

  def normalized_input(values, entity)
    title = values.fetch('title')
    description = values.fetch('description')
    raise ArgumentError unless title.is_a?(String) && title.strip.length.between?(1, 255)
    raise ArgumentError unless description.is_a?(String) && description.strip.length.between?(1, 50_000)

    input = { 'name' => title.strip, 'content' => CGI.escapeHTML(description.strip).gsub("\n", '<br>'), 'entities_id' => entity }
    { 'type' => 2, 'urgency' => 5, 'impact' => 5 }.each do |field, maximum|
      number = JrcServiceDesk::Input.id(values.fetch(field, field == 'type' ? 1 : 3))
      raise ArgumentError unless number <= maximum

      input[field] = number
    end
    if values['category_id'].present?
      category = JrcServiceDesk::Input.id(values['category_id'])
      raise Pundit::NotAuthorizedError unless access.connection.categories.any? do |row|
        row['id'].to_s == category.to_s && row['entity_id'].to_s == entity.to_s
      end

      input['itilcategories_id'] = category
    end
    requester = values['requester_id'].present? ? JrcServiceDesk::Input.id(values['requester_id']) : access.glpi_user_id
    if requester
      allowed = access.connection.user_mappings.any? { |row| row['glpi_user_id'].to_s == requester.to_s }
      raise Pundit::NotAuthorizedError unless allowed && (access.all_tickets? || requester == access.glpi_user_id)

      input['_users_id_requester'] = requester
    end
    input
  end
end
