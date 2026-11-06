# frozen_string_literal: true

class JrcServiceDesk::Intake::Notification
  def call(demand_id:, kind:, operator_context:, request_key:, human_confirmation: false)
    context = JrcServiceDesk::OperationalContext.new(operator_context)
    raise Pundit::NotAuthorizedError unless context.native_operator?

    demand = JrcServiceDesk::IntakeDemand.where(account_id: context.account.id).find(demand_id)
    JrcServiceDesk::Intake::LifecycleLock.call(demand.id) do
      demand.reload
      policy = JrcServiceDesk::Intake::NoticePolicy.new(demand, context.account_user)
      policy.authorize!
      JrcServiceDesk::Intake::NoticePreparation.new(demand, context.account_user).call(
        kind: kind, request_key: request_key, confirmed: human_confirmation
      )
    end
  end

  def observe_message(message_id:)
    notice = JrcServiceDesk::IntakeNotification.find_by(message_id: message_id)
    return unless notice

    JrcServiceDesk::Intake::LifecycleLock.call(notice.intake_demand_id) do
      message = notice.message.reload
      return unless JrcServiceDesk::Intake::NoticePayload.match?(message, notice)
      return unless delivery_proven?(message, notice)

      notice.update!(state: message.status, delivered_at: notice.delivered_at || Time.current)
      start_pending(notice)
      notice
    end
  end

  def complete(demand_id:, operator_context:, source_version:)
    JrcServiceDesk::Intake::HumanCompletion.new.call(demand_id: demand_id, operator_context: operator_context, source_version: source_version)
  end

  def self.eligible?(demand:, channel:)
    settings = demand.intake_configuration.reload.mappings.fetch('notifications', {})
    demand.lifecycle_state == 'completed_human' && demand.completion_cause == 'human' &&
      settings['enabled'] == true && settings['owner'] == 'jrc' && settings['channel'] == channel
  end


  def self.owns_conversation?(conversation)
    latest = JrcServiceDesk::IntakeDemand.where(account_id: conversation.account_id, conversation_id: conversation.id).order(id: :desc).first
    return false unless latest
    return true if latest.completion_cause == 'no_response'

    latest.intake_configuration.mappings.fetch('notifications', {})['owner'] == 'jrc'
  end

  private

  def delivery_proven?(message, notice)
    %w[delivered read].include?(message.status) && message.source_id.present? && notice.state != 'blocked'
  end

  def start_pending(notice)
    return unless notice.kind == 'pending_information'

    JrcServiceDesk::Intake::PendingInformation.new.start(demand_id: notice.intake_demand_id, notice_id: notice.id)
  end
end
