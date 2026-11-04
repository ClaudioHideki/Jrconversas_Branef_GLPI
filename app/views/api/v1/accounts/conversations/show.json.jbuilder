json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: @conversation
json.contact_inbox @conversation.contact_inbox&.as_json(only: [:id, :contact_id, :inbox_id, :source_id])
if Current.user.is_a?(User) && Current.account_user
  json.glpi_references JrcServiceDesk::Glpi::LinkedReferences.new.call(
    user_context: { account: Current.account, user: Current.user, account_user: Current.account_user }, conversation_id: @conversation.id)
end
