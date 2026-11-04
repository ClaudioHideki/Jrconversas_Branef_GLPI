# frozen_string_literal: true

class JrcServiceDesk::Glpi::Execute
  ENTITY_KINDS = { 'Ticket' => 'tickets', 'Problem' => 'problems', 'Change' => 'changes', 'KnowbaseItem' => 'knowledge',
    'ITILCategory' => 'categories', 'TicketTemplate' => 'templates' }.freeze
  REFERENCES = { '_users_id_assign' => 'User', '_users_id_requester' => 'User', 'users_id' => 'User',
    'users_id_tech' => 'User', 'users_id_validate' => 'User', '_groups_id_assign' => 'Group', 'groups_id' => 'Group',
    'groups_id_tech' => 'Group', 'suppliers_id' => 'Supplier', 'problems_id' => 'Problem', 'changes_id' => 'Change',
    'knowbaseitems_id' => 'KnowbaseItem', 'documents_id' => 'Document', 'itilcategories_id' => 'ITILCategory',
    'taskcategories_id' => 'TaskCategory', 'solutiontypes_id' => 'SolutionType', 'tickettemplates_id' => 'TicketTemplate' }.freeze

  def initialize(client_factory: ->(connection) { JrcServiceDesk::Glpi::Client.new(connection) })
    @client_factory = client_factory
  end

  def call(access:, operation:, target_id:, entity_id:, attributes:, idempotency_key:, expected_version: nil, reason: nil,
           legacy_fingerprint: nil, prepared: false)
    contract = JrcServiceDesk::Glpi::CommandInput.new(operation: operation, target_id: target_id, entity_id: entity_id,
      attributes: attributes, expected_version: expected_version, reason: reason, prepared: prepared)
    access = fresh_access(access)
    authorize_local!(access, contract.descriptor)
    unit = access.unit_for(contract.entity_id)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = legacy_fingerprint || contract.fingerprint(access.connection.lock_version)
    scope = JrcServiceDesk::GlpiCommand.where(account_id: access.context.account.id, glpi_connection: access.connection,
      account_user: access.context.account_user)
    if (existing = scope.find_by(idempotency_key: key))
      return existing_receipt(existing, fingerprint, access)
    end
    # A caller transaction would otherwise make the intent disappear after a remote write.
    raise JrcServiceDesk::Glpi::Error.new('durable_intent_requires_commit', 422) if JrcServiceDesk::GlpiCommand.connection.transaction_open?

    command = scope.create!(unit_id: unit, entity_id: contract.entity_id, idempotency_key: key, fingerprint: fingerprint,
      operation: operation, itemtype: contract.descriptor[:type], target_id: contract.target_id, parent_id: contract.parent_id,
      parent_type: contract.descriptor[:parent], connection_version: access.connection.lock_version,
      expected_version: expected_version, reason: reason, content_format: contract.content_format,
      request_payload: contract.input, correlation_id: SecureRandom.uuid)
    with_object_lock(command) { perform(command, access, contract.descriptor) }
    command.reload.receipt
  rescue ActiveRecord::RecordNotUnique
    existing_receipt(scope.find_by!(idempotency_key: key), fingerprint, fresh_access(access))
  end

  # Session advisory locks serialize local senders without holding an uncommitted
  # audit transaction around network I/O. They cannot lock edits made in GLPI itself.
  def with_object_lock(command)
    object = [command.glpi_connection_id, command.parent_type || command.itemtype,
              command.parent_id || command.target_id || command.idempotency_key]
    key = Digest::SHA256.hexdigest(object.join('/'))[0, 15].to_i(16)
    JrcServiceDesk::GlpiCommand.connection_pool.with_connection do |connection|
      connection.execute("SELECT pg_advisory_lock(#{key})")
      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end

  def fresh_access(access, version = access.connection&.lock_version)
    fresh = JrcServiceDesk::Glpi::Access.new(access.context.to_h).ready!
    unless fresh.connection.id == access.connection.id && fresh.connection.lock_version == version
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end
    fresh
  end

  def authorize_local!(access, descriptor)
    raise Pundit::NotAuthorizedError unless access.context.capability?(descriptor[:capability].to_sym)
    raise Pundit::NotAuthorizedError if descriptor[:admin] && !access.context.administrator?
  end

  def authorize_objects!(access, client, command, descriptor, after_write: false)
    query = JrcServiceDesk::Glpi::ResourceQuery.new
    parent = nil
    if descriptor[:parent]
      parent = query.raw(access: access, client: client, kind: ENTITY_KINDS.fetch(descriptor[:parent]), id: command.parent_id)
      verify_entity!(parent, command.entity_id) unless descriptor[:parent] == 'KnowbaseItem'
      if !after_write && !command.target_id && command.expected_version && parent['date_mod'].to_s != command.expected_version
        raise JrcServiceDesk::Glpi::Error.new('version_conflict', 409)
      end
    end
    row = nil
    if command.target_id
      row = client.get("#{command.itemtype}/#{command.target_id}")
      verify_id!(row, command.target_id)
      if descriptor[:parent]
        verify_parent!(row, command, descriptor)
      else
        query.authorize_record!(access, client, command.itemtype, row)
        if command.itemtype == 'KnowbaseItem'
          visible = client.collection("KnowbaseItem/#{command.target_id}/Entity_KnowbaseItem/").any? do |link|
            link['knowbaseitems_id'].to_s == command.target_id.to_s && link['entities_id'].to_s == command.entity_id.to_s
          end
          raise Pundit::NotAuthorizedError unless visible
        else
          expected_entity = after_write ? command.request_payload.fetch('entities_id', command.entity_id) : command.entity_id
          verify_entity!(row, expected_entity)
        end
      end
      if [1, '1', true].include?(row['is_private']) && !access.context.capability?(:technical_notes)
        raise Pundit::NotAuthorizedError
      end
      if !after_write && command.expected_version && row['date_mod'].to_s != command.expected_version
        raise JrcServiceDesk::Glpi::Error.new('version_conflict', 409)
      end
    end
    payload = command.request_payload
    if (payload.keys & %w[begin end]).any?
      planning = (row || {}).slice('begin', 'end').merge(payload.slice('begin', 'end'))
      valid_dates = %w[begin end].all? do |field|
        value = planning[field]
        value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)
      end
      unless valid_dates && planning['begin'] < planning['end']
        raise JrcServiceDesk::Glpi::Error.new('invalid_planning', 422)
      end
    end
    access.unit_for(payload['entities_id']) if payload.key?('entities_id')
    if payload['is_private'] == 1 && !access.context.capability?(:technical_notes)
      raise Pundit::NotAuthorizedError
    end
    linked_types = %w[Ticket_User Group_Ticket Supplier_Ticket Problem_Ticket Change_Ticket KnowbaseItem_Item Document_Item Item_Ticket
                      Problem_User Group_Problem Change_User Change_Group]
    reference_values = linked_types.include?(command.itemtype) && row ? row.slice(*REFERENCES.keys).merge(payload) : payload
    REFERENCES.each do |field, type|
      next unless reference_values[field].to_i.positive?

      related = client.get("#{type}/#{reference_values[field]}")
      verify_id!(related, reference_values[field])
      if type == 'Document'
        verify_entity!(related, command.entity_id)
      else
        query.authorize_record!(access, client, type, related)
      end
    end
    if command.itemtype == 'Item_Ticket'
      asset = descriptor[:verb] == 'post' ? payload : row
      type = asset.fetch('itemtype')
      raise Pundit::NotAuthorizedError unless JrcServiceDesk::Glpi::ResourceQuery::ASSET_TYPES.include?(type)

      related = client.get("#{type}/#{asset.fetch('items_id')}")
      verify_id!(related, asset['items_id'])
      query.authorize_record!(access, client, type, related)
    end
    [row, parent]
  end

  def verify_readback!(access, client, command, descriptor, id, acknowledged: false)
    if descriptor[:verb] == 'delete'
      begin
        row = client.get("#{command.itemtype}/#{id}")
        verify_id!(row, id)
        raise JrcServiceDesk::Glpi::Error.new('write_not_confirmed') unless acknowledged && row['is_deleted'].to_i == 1
      rescue JrcServiceDesk::Glpi::Error => error
        raise unless acknowledged && error.code == 'ERROR_ITEM_NOT_FOUND' && error.http_status == 404
      end
      return { 'verified' => true, 'deleted' => true, 'remote_id' => id.to_s }
    end
    row = client.get("#{command.itemtype}/#{id}")
    verify_id!(row, id)
    if descriptor[:parent]
      verify_parent!(row, command, descriptor)
      parent = client.get("#{command.parent_type}/#{command.parent_id}")
      verify_id!(parent, command.parent_id)
      verify_entity!(parent, command.entity_id)
      access.authorize_ticket!(client, parent) if command.parent_type == 'Ticket'
      if command.operation.end_with?('.solve') && ![5, 6].include?(parent['status'].to_i)
        raise JrcServiceDesk::Glpi::Error.new('write_not_confirmed')
      end
    elsif command.itemtype != 'KnowbaseItem'
      verify_entity!(row, command.request_payload.fetch('entities_id', command.entity_id))
    end
    command.request_payload.each do |field, expected|
      matched = if field == '_visibility'
                  client.collection("KnowbaseItem/#{id}/Entity_KnowbaseItem/").any? do |link|
                    link['knowbaseitems_id'].to_s == id.to_s && link['entities_id'].to_s == command.entity_id.to_s
                  end
                elsif %w[_users_id_assign _groups_id_assign _users_id_requester].include?(field)
                  actor_matches?(client, command.itemtype, id, field, expected)
                elsif field == 'knowbaseitemcategories_id'
                  client.collection("KnowbaseItem/#{id}/KnowbaseItem_KnowbaseItemCategory/").any? do |link|
                    link['knowbaseitems_id'].to_s == id.to_s && link[field].to_s == expected.to_s
                  end
                elsif %w[content answer].include?(field) && command.content_format == 'rich'
                  JrcServiceDesk::Glpi::Content.rich(row[field], from_source: true) == JrcServiceDesk::Glpi::Content.rich(expected)
                else
                  equivalent?(row[field], expected)
                end
      raise JrcServiceDesk::Glpi::Error.new('write_not_confirmed') unless matched
    end
    { 'verified' => true, 'remote_id' => id.to_s, 'fields' => command.request_payload.keys.reject { |key| key.start_with?('_') },
      'date_mod' => row['date_mod'], 'atomic_compare_and_swap' => false }
  end

  def verify_parent!(row, command, descriptor)
    raise Pundit::NotAuthorizedError unless row[descriptor.fetch(:parent_field)].to_s == command.parent_id.to_s
    if descriptor[:defaults].key?('itemtype') && row['itemtype'] != command.parent_type
      raise Pundit::NotAuthorizedError
    end
  end

  def verify_id!(row, id)
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless row.is_a?(Hash) && row['id'].to_s == id.to_s
  end

  def verify_entity!(row, entity)
    raise Pundit::NotAuthorizedError unless row['entities_id'].to_s == entity.to_s
  end

  private

  def perform(command, access, descriptor)
    sent = false
    write_acknowledged = false
    @client_factory.call(access.connection).session do |client|
      access = fresh_access(access, command.connection_version)
      authorize_local!(access, descriptor)
      access.unit_for(command.entity_id)
      unresolved!(command)
      profile = client.get('getActiveProfile/').fetch('active_profile')
      identity = client.get('getFullSession/').fetch('session')
      technical_id = JrcServiceDesk::Input.id(identity.fetch('glpiID'))
      command.update!(technical_user_id: technical_id)
      before, parent = authorize_objects!(access, client, command, descriptor)
      authorize_source!(profile, command, descriptor, before, parent, technical_id)
      payload = command.request_payload.deep_dup
      if descriptor[:verb] == 'post' && (field = %w[content answer].find { |key| payload.key?(key) })
        payload[field] += "<p>#{command.correlation_marker}</p>"
      end
      command.update!(state: 'sending', before_values: before&.slice('date_mod', *payload.keys), request_payload: payload)
      # All reads above can take time; refresh identity/configuration immediately before send.
      access = fresh_access(access, command.connection_version)
      authorize_local!(access, descriptor)
      access.unit_for(command.entity_id)
      sent = true
      response = case descriptor[:verb]
                 when 'post' then client.create_item(command.itemtype, payload)
                 when 'patch' then client.update_item(command.itemtype, command.target_id, payload)
                 when 'delete' then client.delete_item(command.itemtype, command.target_id)
                 end
      id = descriptor[:verb] == 'post' ? JrcServiceDesk::Input.id(response.fetch('id')) : command.target_id
      command.update!(remote_id: id)
      acknowledge!(response, id, descriptor[:verb])
      write_acknowledged = true
      access = fresh_access(access, command.connection_version)
      authorize_local!(access, descriptor)
      result = verify_readback!(access, client, command, descriptor, id, acknowledged: true)
      command.update!(state: 'succeeded', result: result, error_code: nil)
    end
  rescue Pundit::NotAuthorizedError
    command.update!(state: sent ? 'indeterminate' : 'rejected', error_code: 'not_authorized')
  rescue JrcServiceDesk::Glpi::Error => error
    definitive = !sent || (!write_acknowledged && (error.http_status == 403 || error.code == 'source_write_rejected'))
    command.update!(state: definitive ? 'rejected' : 'indeterminate', error_code: error.code)
  rescue KeyError, ArgumentError, TypeError
    command.update!(state: sent ? 'indeterminate' : 'rejected', error_code: 'invalid_response')
  end

  def existing_receipt(command, fingerprint, access)
    raise JrcServiceDesk::IdempotencyConflict unless command.fingerprint == fingerprint

    access.unit_for(command.entity_id)
    command.receipt
  end

  def unresolved!(command)
    scope = JrcServiceDesk::GlpiCommand.where(glpi_connection_id: command.glpi_connection_id, state: %w[sending indeterminate]).where.not(id: command.id)
    type = command.parent_type || command.itemtype
    id = command.parent_id || command.target_id
    scope = scope.where(parent_type: type, parent_id: id).or(scope.where(itemtype: type, target_id: id))
    raise JrcServiceDesk::Glpi::Error.new('unresolved_previous_command', 409) if (command.target_id || command.parent_id) && scope.exists?
  end

  def authorize_source!(profile, command, descriptor, row, parent, technical_id)
    alternatives = [descriptor[:source_right]] + descriptor[:source_alternatives]
    if command.itemtype == 'TicketValidation'
      incident = parent.fetch('type').to_i == 1
      mask = command.operation.end_with?('.decide') ? (incident ? 8192 : 4096) : (incident ? 2048 : 1024)
      alternatives = [['ticketvalidation', mask]]
    end
    allowed = alternatives.any? { |right, mask| (profile.fetch(right, 0).to_i & mask).positive? }
    raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) unless allowed
    if command.operation.end_with?('.decide') && row['users_id_validate'].to_s != technical_id.to_s
      raise JrcServiceDesk::Glpi::Error.new('technical_validator_mismatch', 403)
    end
    if command.itemtype == 'ITILFollowup' && descriptor[:verb] == 'patch'
      mask = row['users_id'].to_s == technical_id.to_s ? 2 : 1024
      raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) if (profile.fetch('followup', 0).to_i & mask).zero?
    end
  end

  def acknowledge!(response, id, verb)
    return if verb == 'post' && response.is_a?(Hash) && response['id'].to_s == id.to_s
    return if response.is_a?(Hash) && response['id'].to_s == id.to_s && (verb != 'delete' || response['deleted'] == true)
    return if response.is_a?(Array) && response.any? { |row| row.is_a?(Hash) && row[id.to_s] == true }

    code = response.is_a?(Array) && response.any? { |row| row.is_a?(Hash) && row[id.to_s] == false } ? 'source_write_rejected' : 'invalid_response'
    raise JrcServiceDesk::Glpi::Error.new(code)
  end

  def actor_matches?(client, type, id, field, expected)
    group = field == '_groups_id_assign'
    relation = group ? JrcServiceDesk::Glpi::OperationCatalogue::GROUP_RELATIONS.fetch(type) : "#{type}_User"
    key = group ? 'groups_id' : 'users_id'
    actor_type = field == '_users_id_requester' ? 1 : 2
    actors = client.collection("#{type}/#{id}/#{relation}/").to_a
    raise Pundit::NotAuthorizedError unless actors.all? { |actor| actor["#{type.downcase}s_id"].to_s == id.to_s }

    expected.to_i.zero? ? actors.none? { |actor| actor['type'].to_i == actor_type } :
      actors.any? { |actor| actor[key].to_s == expected.to_s && actor['type'].to_i == actor_type }
  end

  def equivalent?(actual, expected)
    if expected.is_a?(String)
      JrcServiceDesk::Glpi::Normalize.text(actual) == JrcServiceDesk::Glpi::Normalize.text(expected)
    else
      actual.to_s == expected.to_s
    end
  end
end
