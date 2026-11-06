# frozen_string_literal: true

class JrcServiceDeskIntakeListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    observe(message.conversation_id, message.id)
  end

  def message_updated(event)
    message_created(event)
  end

  def conversation_updated(event)
    observe(event.data[:conversation].id)
  end

  private

  def observe(conversation_id, message_id = nil)
    return unless JrcServiceDesk::IntakeDemand.where(conversation_id: conversation_id).exists?

    JrcServiceDesk::IntakeObservationJob.perform_later(conversation_id, message_id)
  end
end
