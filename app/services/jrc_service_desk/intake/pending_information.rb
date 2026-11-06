# frozen_string_literal: true

class JrcServiceDesk::Intake::PendingInformation
  def start(demand_id:, notice_id:)
    JrcServiceDesk::Intake::LifecycleLock.call(demand_id) do
      demand = JrcServiceDesk::IntakeDemand.find(demand_id)
      notice = JrcServiceDesk::IntakeNotification.find_by!(id: notice_id, intake_demand_id: demand.id,
        account_id: demand.account_id, kind: 'pending_information')
      return demand unless demand.pending_notice_id == notice.id

      control = JrcServiceDesk::Intake::PendingControl.new(demand, notice)
      return cancel(demand) if control.cancelled?
      return demand unless delivered?(notice)
      return demand if demand.waiting_deadline

      control.access!
      demand.update!(lifecycle_state: 'awaiting_information', waiting_deadline: notice.delivered_at + 48.hours,
        waiting_control: control.snapshot)
      JrcServiceDesk::IntakePendingInformationJob.set(wait_until: demand.waiting_deadline).perform_later(demand.id, notice.generation)
      demand
    end
  rescue JrcServiceDesk::Intake::PendingControl::Cancelled, Pundit::NotAuthorizedError
    cancel(demand)
  end

  def expire(demand_id:, generation:)
    JrcServiceDesk::Intake::LifecycleLock.call(demand_id) do
      demand = JrcServiceDesk::IntakeDemand.find(demand_id)
      return demand unless demand.waiting_generation == generation && demand.lifecycle_state == 'awaiting_information'

      control = JrcServiceDesk::Intake::PendingControl.new(demand, demand.pending_notice)
      return cancel(demand) if control.cancelled?
      return demand unless demand.waiting_deadline && Time.current >= demand.waiting_deadline

      JrcServiceDesk::Intake::PendingClosure.new(demand, control).call
      demand.reload
    end
  end

  def cancel_conversation(conversation_id:)
    JrcServiceDesk::IntakeDemand.where(conversation_id: conversation_id, lifecycle_state: %w[awaiting_delivery awaiting_information]).find_each do |demand|
      JrcServiceDesk::Intake::LifecycleLock.call(demand.id) do
        fresh = demand.reload
        next unless fresh.pending_notice

        cancel(fresh) if JrcServiceDesk::Intake::PendingControl.new(fresh, fresh.pending_notice).cancelled?
      end
    end
  end

  private

  def delivered?(notice)
    %w[delivered read].include?(notice.state) && notice.delivered_at &&
      JrcServiceDesk::Intake::NoticePayload.match?(notice.message, notice)
  end

  def cancel(demand)
    demand.update!(lifecycle_state: 'cancelled', waiting_generation: nil, waiting_deadline: nil, lifecycle_error_code: 'intake_pending_cancelled')
    demand
  end
end
