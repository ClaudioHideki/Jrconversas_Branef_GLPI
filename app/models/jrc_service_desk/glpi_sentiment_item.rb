# frozen_string_literal: true

class JrcServiceDesk::GlpiSentimentItem < ApplicationRecord
  belongs_to :batch, class_name: 'JrcServiceDesk::GlpiSentimentBatch', inverse_of: :items
end
