# frozen_string_literal: true

class JrcServiceDesk::Intake::HumanCompletion
  def call(demand_id:, operator_context:, source_version:)
    context = JrcServiceDesk::OperationalContext.new(operator_context)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.capability?(:resolve)

    demand = JrcServiceDesk::IntakeDemand.where(account_id: context.account.id).find(demand_id)
    JrcServiceDesk::Intake::LifecycleLock.call(demand.id) do
      demand.reload
      raise ArgumentError, 'intake_no_response_not_human' if demand.completion_cause == 'no_response'

      policy = JrcServiceDesk::Intake::NoticePolicy.new(demand, context.account_user)
      policy.authorize!
      verify_source!(demand, context, source_version)
      persist(demand, context, source_version)
    end
  end

  private

  def verify_source!(demand, context, version)
    access = JrcServiceDesk::Glpi::Access.new(context.to_h).ready!
    mapping = JrcServiceDesk::Intake::Mapping.new(demand)
    JrcServiceDesk::Glpi::Destination.new(mapping.destination).access!(context.to_h)
    ref = JrcServiceDesk::Glpi::Reference.new(
      'account_id' => demand.account_id, 'connection_id' => access.connection.id, 'itemtype' => 'Ticket',
      'remote_id' => demand.remote_id, 'entity_id' => mapping.route.fetch('entity_id')
    )
    JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      ticket = ref.authorize!(access: access, client: client, operational: true)
      raise ArgumentError, 'intake_completion_unconfirmed' unless [5, 6].include?(ticket['status'].to_i) && ticket['date_mod'] == version
    end
  end

  def persist(demand, context, version)
    receipt = { 'state' => 'succeeded', 'source_version' => version, 'operator_id' => context.account_user.id }
    demand.update!(lifecycle_state: 'completed_human', completion_cause: 'human', completed_at: demand.completed_at || Time.current,
      waiting_generation: nil, waiting_deadline: nil, lifecycle_error_code: nil,
      lifecycle_receipts: demand.lifecycle_receipts.merge('human_completion' => receipt))
    JrcServiceDesk::Intake::Notification.new.call(demand_id: demand.id, kind: 'survey', operator_context: context.to_h,
      request_key: demand.episode_key, human_confirmation: true)
  end
end
