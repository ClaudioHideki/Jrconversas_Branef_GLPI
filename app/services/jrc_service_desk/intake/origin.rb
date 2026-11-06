# frozen_string_literal: true

# Server-derived provenance. Neither declared customer identity nor Flow data grants authority.
class JrcServiceDesk::Intake::Origin
  def self.capture(authority:, context:, conversation:, configuration:)
    values = authority.credential_identity.merge('initiator_type' => 'automation')
    return values unless configuration.remote_writes_enabled?

    integration = JrcBrokerIntegration.find_by!(account_id: context.account.id)
    binding = JrcBrokerInboxBinding.find_by!(account_id: context.account.id, inbox_id: conversation.inbox_id)
    connection = JrcServiceDesk::GlpiConnection.find_by!(account_id: context.account.id)
    values.merge(
      'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id,
      'connection_id' => connection.id, 'connection_version' => connection.lock_version,
      'routing_source_hash' => JrcFlowEffects::ControlRevision.snapshot(conversation).fetch('routing_source_hash'),
      'assignee_id' => conversation.assignee_id, 'assignee_agent_bot_id' => conversation.assignee_agent_bot_id,
      'team_id' => conversation.team_id, 'conversation_status' => conversation.status
    )
  end

  def initialize(demand)
    @demand = demand
  end

  def authorize!(conversation_control: true)
    @demand.reload
    member = AccountUser.find_by!(id: @demand.account_user_id, account_id: @demand.account_id)
    token = AccessToken.find_by!(id: values.fetch('service_token_id'), owner_type: 'User', owner_id: member.user_id)
    digest = Digest::SHA256.hexdigest(token.token)
    raise Pundit::NotAuthorizedError unless ActiveSupport::SecurityUtils.secure_compare(digest, values.fetch('service_token_fingerprint'))

    authority = JrcFlowEffects::Authority.new(account: @demand.account, user: member.user, access_token: token).authorize!
    context = JrcServiceDesk::OperationalContext.new(account: authority.account, user: authority.user, account_user: member)
    validate_binding!(context)
    validate_conversation!(conversation_control)
    context.to_h
  end

  private

  def values = @demand.source_context

  def validate_binding!(context)
    validate_configuration!(context)
    JrcBrokerIntegration.find_by!(account_id: @demand.account_id, organization_id: values.fetch('organization_id'))
    JrcBrokerInboxBinding.find_by!(account_id: @demand.account_id, inbox_id: @demand.inbox_id,
                                   integration_id: values.fetch('integration_id'))
    validate_connection!
  end

  def validate_configuration!(context)
    configuration = @demand.intake_configuration.reload
    valid = configuration.enabled? && configuration.remote_writes_enabled? && context.native_operator? &&
            context.capability?(:tickets_create) && JrcBroker::Configuration.enabled? && context.account.feature_enabled?('jrc_broker')
    raise Pundit::NotAuthorizedError unless valid
  end

  def validate_connection!
    connection = JrcServiceDesk::GlpiConnection.find_by!(account_id: @demand.account_id, id: values.fetch('connection_id'))
    return if connection.enabled? && connection.primary_source? && connection.lock_version == values.fetch('connection_version')

    raise Pundit::NotAuthorizedError
  end

  def validate_conversation!(control)
    target = Conversation.find_by!(id: @demand.conversation_id, account_id: @demand.account_id,
                                   inbox_id: @demand.inbox_id, contact_id: @demand.contact_id)
    validate_routing!(target)
    return unless control

    valid = target.pending? && values['conversation_status'] == 'pending' && target.assignee_id.nil? && target.team_id.nil? &&
            target.assignee_agent_bot_id == values['assignee_agent_bot_id']
    raise Pundit::NotAuthorizedError unless valid
  end

  def validate_routing!(target)
    routing = JrcFlowEffects::ControlRevision.snapshot(target).fetch('routing_source_hash')
    raise Pundit::NotAuthorizedError unless routing == values.fetch('routing_source_hash')
  end
end
