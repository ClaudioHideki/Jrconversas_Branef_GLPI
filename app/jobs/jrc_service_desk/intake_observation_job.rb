# frozen_string_literal: true

class JrcServiceDesk::IntakeObservationJob < ApplicationJob
  queue_as :high
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, message_id = nil)
    JrcServiceDesk::Intake::Notification.new.observe_message(message_id: message_id) if message_id
    JrcServiceDesk::Intake::PendingInformation.new.cancel_conversation(conversation_id: conversation_id)
  end
end
