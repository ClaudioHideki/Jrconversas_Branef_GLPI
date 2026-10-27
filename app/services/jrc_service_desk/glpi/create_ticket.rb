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
    unit = access.unit_for(entity)
    input = normalized_input(values, entity)
    key = JrcServiceDesk::Input.request_key(values.fetch('idempotency_key'))
    fingerprint = JrcServiceDesk::CanonicalJson.digest(input.merge('connection_version' => access.connection.lock_version))
    scope = JrcServiceDesk::GlpiCommand.where(account_id: access.context.account.id, glpi_connection: access.connection,
                                             account_user: access.context.account_user)
    existing = scope.find_by(idempotency_key: key)
    return existing_receipt(existing, fingerprint) if existing

    sent = false
    command = scope.create!(unit_id: unit, entity_id: entity, idempotency_key: key, fingerprint: fingerprint,
                            correlation_id: SecureRandom.uuid)
    command.update!(state: 'sending')
    # The committed receipt precedes network I/O. Never retry an ambiguous POST.
    JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      profile = client.get('getActiveProfile/').fetch('active_profile')
      raise JrcServiceDesk::Glpi::Error.new('creation_not_permitted', 403) if (profile.fetch('ticket', 0).to_i & 4).zero?

      sent = true
      response = client.create_ticket(input.merge('content' => input.fetch('content') + "<p>#{command.correlation_marker}</p>"))
      remote_id = JrcServiceDesk::Input.id(response.fetch('id'))
      command.update!(state: 'succeeded', remote_id: remote_id)
    end
    command.receipt
  rescue ActiveRecord::RecordNotUnique
    existing_receipt(scope.find_by!(idempotency_key: key), fingerprint)
  rescue JrcServiceDesk::Glpi::Error => error
    if command
      definitive = !sent || %w[creation_not_permitted ERROR_RIGHT_MISSING ERROR_GLPI_ADD ERROR_BAD_ARRAY ERROR_APP_TOKEN_PARAMETERS_MISSING
                      ERROR_WRONG_APP_TOKEN_PARAMETER ERROR_SESSION_TOKEN_INVALID].include?(error.code)
      command.update!(state: definitive ? 'rejected' : 'indeterminate', error_code: error.code)
      command.receipt
    else
      raise
    end
  rescue KeyError, ArgumentError
    if command
      command.update!(state: 'indeterminate', error_code: 'invalid_response')
      command.receipt
    else
      raise
    end
  end

  private

  attr_reader :access

  def existing_receipt(command, fingerprint)
    raise JrcServiceDesk::IdempotencyConflict unless command.fingerprint == fingerprint

    access.unit_for(command.entity_id)
    command.receipt
  end

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
