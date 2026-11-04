# frozen_string_literal: true

class JrcServiceDesk::Glpi::AutomationCommand
  def call(user_context:, reference:, operation:, attributes:, idempotency_key:, expected_version: nil, reason: nil, target_id: nil)
    ref = JrcServiceDesk::Glpi::Reference.new(reference)
    access = JrcServiceDesk::Glpi::Access.new(user_context).ready!
    descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch(operation)
    values = ref.values
    raise ArgumentError if target_id && (descriptor[:verb] == 'post' || !descriptor[:parent])
    if descriptor[:parent]
      raise ArgumentError unless descriptor[:parent] == values['itemtype']
      raise ArgumentError if attributes.stringify_keys.key?('parent_id') && attributes.stringify_keys['parent_id'].to_s != values['remote_id'].to_s

      attributes = attributes.stringify_keys.merge('parent_id' => values['remote_id'])
      target = descriptor[:verb] == 'post' ? nil : JrcServiceDesk::Input.id(target_id)
    else
      raise ArgumentError unless descriptor[:verb] != 'post' && descriptor[:type] == values['itemtype']

      target = values['remote_id']
    end
    JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      ref.authorize!(access: access, client: client, operational: true)
    end
    # Execute performs its own fresh checks, durable receipt, technical attribution and readback.
    JrcServiceDesk::Glpi::Execute.new.call(access: access, operation: operation, target_id: target,
      entity_id: values['entity_id'], attributes: attributes, idempotency_key: idempotency_key,
      expected_version: expected_version, reason: reason)
  end
end
