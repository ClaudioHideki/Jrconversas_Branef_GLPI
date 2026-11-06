# frozen_string_literal: true

# Native SendReplyJob/Webhooks::Trigger retain the provider boundary. No retry can repeat an uncertain dispatch.
class JrcServiceDesk::Intake::NoticeExecution
  def initialize(message)
    @message = message
  end

  def perform
    scope = JrcServiceDesk::IntakeNotification.where(account_id: @message.account_id, conversation_id: @message.conversation_id, message_id: @message.id)
    @notice = scope.find_by(id: @message.content_attributes['service_desk_intake_notice_id'])
    return unless @notice && claim

    yield
    @message.reload
    state = if @message.failed?
              'failed'
            else
              @message.source_id.present? ? 'sent' : 'unknown'
            end
    @notice.update!(state: state)
    JrcServiceDesk::Intake::Notification.new.observe_message(message_id: @message.id)
  rescue StandardError
    @notice&.update!(state: 'unknown', reason_code: 'provider_result_unverified')
  end

  private

  def claim
    @notice.with_lock do
      if @notice.state == 'sending'
        @notice.update!(state: 'unknown', reason_code: 'previous_dispatch_unverified')
        next false
      end
      next false unless @notice.state == 'queued'

      reason = JrcServiceDesk::Intake::NoticeGuard.new(@notice).blocker
      reason ||= 'message_payload_changed' unless JrcServiceDesk::Intake::NoticePayload.match?(@message.reload, @notice)
      next block(reason) if reason

      @notice.update!(state: 'sending')
      true
    end
  end

  def block(reason)
    @notice.update!(state: 'blocked', reason_code: reason)
    @message.update!(status: :failed)
    false
  end
end
