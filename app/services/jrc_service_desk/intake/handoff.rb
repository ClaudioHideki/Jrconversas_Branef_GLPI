# frozen_string_literal: true

# Admits only local work. GLPI delivery starts after this transaction commits.
class JrcServiceDesk::Intake::Handoff
  def call(authority:, conversation:, arguments:, operation_id:)
    @authority = authority
    @conversation = conversation
    @arguments = arguments
    @operation_id = operation_id
    raise ArgumentError, 'intake_handoff_control' unless conversation.pending? && conversation.assignee_id.nil? && conversation.team_id.nil?

    target = authorized_target!
    intake, error = admit
    conversation.update!(target.merge(status: :open, assignee_agent_bot_id: nil, waiting_since: conversation.waiting_since || Time.current))
    note(intake, error)
    { 'command' => 'service_desk_handoff', 'resource_type' => 'Conversation', 'resource_id' => conversation.id,
      'created' => false, 'delivery' => 'NOT_APPLICABLE', 'episode_key' => arguments.fetch('episode_key'),
      'configuration_id' => arguments.fetch('configuration_id').to_s,
      'handoff' => { 'conversation_id' => conversation.display_id, 'inbox_id' => conversation.inbox_id,
                     'team_id' => conversation.team_id, 'agent_id' => conversation.assignee_id },
      'intake' => intake&.deep_stringify_keys, 'error_code' => error,
      'event' => { 'id' => operation_id, 'causation_id' => operation_id, 'type' => 'service_desk.handoff.recorded' } }
  end

  def authorize_receipt!(account:, user:, conversation:, result:)
    member = account.account_users.find_by!(user_id: user.id)
    context = JrcServiceDesk::OperationalContext.new(account: account, user: user, account_user: member)
    valid = context.native_operator? && context.capability?(:tickets_create) && result['resource_type'] == 'Conversation' &&
            result['resource_id'] == conversation.id && result.dig('handoff', 'inbox_id') == conversation.inbox_id &&
            result.dig('handoff', 'conversation_id') == conversation.display_id
    raise Pundit::NotAuthorizedError unless valid

    conversation
  end

  private

  def authorized_target!
    values = @arguments.fetch('target')
    if values['team_id']
      team = @authority.account.teams.lock('FOR SHARE').find(values['team_id'])
      return { team_id: team.id, assignee_id: nil }
    end
    member = @authority.account.account_users.lock('FOR SHARE').find_by!(user_id: values.fetch('agent_id'))
    @conversation.inbox.inbox_members.lock('FOR SHARE').find_by!(user_id: member.user_id)
    raise Pundit::NotAuthorizedError unless member.user.active_for_authentication? && member.user.confirmed?

    { team_id: nil, assignee_id: member.user_id }
  end

  def admit
    return [nil, @arguments.fetch('capture_error')] if @arguments['capture_error']

    receipt = JrcServiceDesk::IntakeDemand.transaction(requires_new: true) do
      result = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation,
                                                           arguments: @arguments.except('command', 'target', 'capture_error'),
                                                           handoff_operation_id: @operation_id)
      demand = JrcServiceDesk::IntakeDemand.find(result.fetch(:id))
      prior = demand.source_context['handoff_operation_id']
      raise ArgumentError, 'intake_handoff_conflict' unless prior == @operation_id

      result
    end
    [receipt, nil]
  rescue ArgumentError, KeyError, ActiveRecord::RecordInvalid
    [nil, 'intake_collection_invalid']
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    [nil, 'intake_not_ready']
  end

  def note(intake, error)
    status = error || intake&.fetch(:state)
    body = "Atendimento encaminhado à equipe. Registro GLPI: #{status}. Nenhum protocolo remoto foi confirmado nesta transferência.\n\n" \
           "Dados da coleta:\n#{JSON.pretty_generate(@arguments.fetch('input'))}"
    Messages::MessageBuilder.new(@authority.user, @conversation, content: body, private: true).perform
  end
end
