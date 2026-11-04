# frozen_string_literal: true

class JrcServiceDesk::Glpi::LinkLocalReference
  def call(user_context:, reference:, conversation_id: nil, incident_id: nil)
    raise ArgumentError unless conversation_id.nil? != incident_id.nil?

    access = JrcServiceDesk::Glpi::Access.new(user_context).ready!
    ref = JrcServiceDesk::Glpi::Reference.new(reference)
    ref.authorize_local!(access: access, operational: true)
    capability = conversation_id ? :conversations_link : :incidents_manage
    raise Pundit::NotAuthorizedError unless access.context.capability?(capability)

    model = conversation_id ? Conversation : JrcServiceDesk::Incident
    local = model.where(account_id: access.context.account.id).find(JrcServiceDesk::Input.id(conversation_id || incident_id))
    Pundit.authorize(access.context.to_h, local, :show?)
    if incident_id && local.unit_id != access.unit_for(ref.values['entity_id'])
      raise Pundit::NotAuthorizedError
    end
    record = JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      ref.authorize!(access: access, client: client, operational: true)
      ref.record!(access: access, client: client)
    end
    fresh = JrcServiceDesk::Glpi::Access.new(user_context).ready!
    if fresh.connection.lock_version != access.connection.lock_version
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end
    ref.authorize_local!(access: fresh, operational: true)
    Pundit.authorize(fresh.context.to_h, local.reload, :show?)
    key = conversation_id ? { conversation_id: local.id } : { incident_id: local.id }
    JrcServiceDesk::GlpiReferenceLink.find_or_create_by!(glpi_reference: record, **key) do |link|
      link.account_id = access.context.account.id
      link.unit_id = record.unit_id
      link.account_user_id = access.context.account_user.id
    end
  end
end
