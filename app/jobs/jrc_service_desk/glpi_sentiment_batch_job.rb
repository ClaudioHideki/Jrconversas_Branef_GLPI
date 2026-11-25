# frozen_string_literal: true

class JrcServiceDesk::GlpiSentimentBatchJob < ApplicationJob
  queue_as :low

  def perform(batch_id = nil)
    if batch_id.nil?
      JrcServiceDesk::GlpiSentimentBatch.active.where(updated_at: ...2.minutes.ago).find_each do |batch|
        self.class.perform_later(batch.id)
      end
      return
    end

    batch = JrcServiceDesk::GlpiSentimentBatch.active.find_by(id: batch_id)
    return unless batch

    delay = JrcServiceDesk::Glpi::SentimentBatch.new.step(batch)
    if batch.reload.state == 'running' && !batch.items.exists?(state: 'running')
      self.class.set(wait: delay.is_a?(ActiveSupport::Duration) ? delay : 3.seconds).perform_later(batch.id)
    end
  end
end
