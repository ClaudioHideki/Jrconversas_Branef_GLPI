# frozen_string_literal: true

class JrcServiceDesk::Intake::DomainCommand
  def call(authority:, conversation:, arguments:, operation_id:)
    receipt = if arguments.fetch('command') == 'service_desk_intake'
                JrcServiceDesk::Intake::Submission.new.call(authority: authority, conversation: conversation,
                  arguments: arguments.except('command'))
              else
                demand = scoped_demand(authority.account, authority.user, conversation, arguments.fetch('episode_key'))
                demand.receipt
              end
    { 'command' => arguments.fetch('command'), 'resource_type' => 'JrcServiceDesk::IntakeDemand',
      'resource_id' => JrcServiceDesk::Input.id(receipt.fetch(:id)), 'created' => receipt.fetch(:created),
      'delivery' => 'NOT_APPLICABLE', 'intake' => receipt.deep_stringify_keys,
      'event' => { 'id' => operation_id, 'causation_id' => operation_id, 'type' => 'service_desk.intake.recorded' } }
  end

  def authorize_receipt!(account:, user:, conversation:, result:)
    unless JrcDomainCommands::Request::INTAKE_COMMANDS.include?(result['command']) && result['resource_type'] == 'JrcServiceDesk::IntakeDemand'
      raise ArgumentError, 'intake_receipt'
    end
    demand = scoped_demand(account, user, conversation, result.fetch('intake').fetch('episode_key'))
    raise Pundit::NotAuthorizedError unless demand.id == result.fetch('resource_id')

    demand
  end

  private

  def scoped_demand(account, user, conversation, episode_key)
    member = account.account_users.find_by!(user_id: user.id)
    context = JrcServiceDesk::OperationalContext.new(account: account, user: user, account_user: member)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.capability?(:tickets_create)

    demand = JrcServiceDesk::IntakeDemand.where(account_id: account.id, inbox_id: conversation.inbox_id,
      conversation_id: conversation.id, contact_id: conversation.contact_id, account_user_id: member.id).find_by!(episode_key: episode_key)
    raise Pundit::NotAuthorizedError unless demand.intake_configuration.reload.enabled?

    demand
  end
end
