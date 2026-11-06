# frozen_string_literal: true

class JrcServiceDesk::Intake::NoticePayload
  def self.digest(message, notice)
    JrcServiceDesk::CanonicalJson.digest(
      account_id: message.account_id, inbox_id: message.inbox_id, conversation_id: message.conversation_id,
      contact_id: message.conversation.contact_id, contact_inbox_id: message.conversation.contact_inbox_id,
      content: message.content, content_attributes: message.content_attributes, private: message.private?,
      content_type: message.content_type, additional_attributes: message.additional_attributes, attachments: attachments(message),
      message_type: message.message_type, sender_type: message.sender_type, sender_id: message.sender_id,
      recipient_digest: notice.recipient_digest, configuration_id: notice.intake_demand.intake_configuration_id,
      binding: JrcBroker::OutboundChannel.configuration(message.inbox)
    )
  end

  def self.attachments(message)
    message.attachments.order(:id).map do |attachment|
      blob = attachment.file.blob
      { id: attachment.id, file_type: attachment.file_type, blob_id: blob&.id, checksum: blob&.checksum, byte_size: blob&.byte_size }
    end
  end

  def self.match?(message, notice)
    message && message.account_id == notice.account_id && message.conversation_id == notice.conversation_id &&
      message.inbox_id == notice.inbox_id && message.content_attributes['service_desk_intake_notice_id'].to_s == notice.id.to_s &&
      notice.payload_digest.present? && digest(message, notice) == notice.payload_digest
  end
end
