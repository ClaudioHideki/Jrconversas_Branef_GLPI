# frozen_string_literal: true

class JrcServiceDesk::IntakeNotificationJob < ApplicationJob
  queue_as :high
  discard_on ActiveRecord::RecordNotFound

  def perform(id)
    notice = JrcServiceDesk::IntakeNotification.find(id)
    JrcServiceDesk::Intake::LifecycleLock.call(notice.intake_demand_id) do
      notice.with_lock do
        next unless notice.state == 'queued' && notice.message_id.nil?

        policy = JrcServiceDesk::Intake::NoticePolicy.new(notice.intake_demand, notice.account_user)
        reason = JrcServiceDesk::Intake::NoticeGuard.new(notice).blocker
        if reason
          notice.update!(state: 'blocked', reason_code: reason)
          next
        end
        build_message(notice, policy.context)
      end
    end
  end

  private

  def build_message(notice, context)
    message = JrcServiceDesk::NativeExecutionContext.with(context.to_h) do
      Messages::MessageBuilder.new(nil, notice.conversation,
                                   content: notice.rendered_payload, message_type: 'outgoing', private: false,
                                   content_attributes: { service_desk_intake_notice_id: notice.id }).perform
    end
    notice.update!(message: message, payload_digest: JrcServiceDesk::Intake::NoticePayload.digest(message, notice))
  end
end
