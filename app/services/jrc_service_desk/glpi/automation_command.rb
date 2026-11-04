# frozen_string_literal: true

class JrcServiceDesk::Glpi::AutomationCommand
  def initialize(authorizer: nil)
    @authorizer = authorizer
  end

  def create(user_context:, destination:, attributes:, idempotency_key:, template_version: nil)
    binding = JrcServiceDesk::Glpi::Destination.new(destination)
    access = binding.access!(user_context)
    executor = JrcServiceDesk::Glpi::Execute.new(access_authorizer: lambda do |fresh|
      binding.access!(fresh.context.to_h)
      @authorizer&.call
    end)
    executor.call(access: access, operation: 'ticket.create', target_id: nil,
      entity_id: binding.values.fetch('entity_id'), attributes: attributes, idempotency_key: idempotency_key,
      template_version: template_version)
  end

  def call(user_context:, reference:, operation:, attributes:, idempotency_key:, expected_version: nil, reason: nil, target_id: nil)
    ref = JrcServiceDesk::Glpi::Reference.new(reference)
    access = JrcServiceDesk::Glpi::Access.new(user_context).ready!
    ref.authorize_local!(access: access, operational: true)
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
    # Execute verifies the live target/parent after persisting intent, before any source write.
    executor = JrcServiceDesk::Glpi::Execute.new(access_authorizer: lambda do |fresh|
      ref.authorize_local!(access: fresh, operational: true)
      @authorizer&.call
    end)
    executor.call(access: access, operation: operation, target_id: target,
      entity_id: values['entity_id'], attributes: attributes, idempotency_key: idempotency_key,
      expected_version: expected_version, reason: reason)
  end
end
