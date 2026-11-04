# frozen_string_literal: true

class JrcServiceDesk::Glpi::LinkLocalReference
  def initialize(authorizer: nil)
    @authorizer = authorizer
  end

  def call(user_context:, reference:, conversation_id: nil, incident_id: nil)
    @authorizer&.call
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
      ref.record!(access: access, client: client, operational: true)
    end
    Account.transaction do
      Account.where(id: access.context.account.id).lock('FOR SHARE').take!
      fresh = ref.authorize_local!(access: access, operational: true)
      Pundit.authorize(fresh.context.to_h, local.reload, :show?)
      @authorizer&.call
      key = conversation_id ? { conversation_id: local.id } : { incident_id: local.id }
      JrcServiceDesk::GlpiReferenceLink.create_or_find_by!(glpi_reference: record, **key) do |link|
        link.account_id = fresh.context.account.id
        link.unit_id = record.unit_id
        link.account_user_id = fresh.context.account_user.id
      end
    end
  end
end
