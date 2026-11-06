# frozen_string_literal: true

class JrcServiceDesk::IntakeDeliveryJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(demand_id)
    JrcServiceDesk::Intake::Delivery.new.call(demand_id: demand_id)
  end
end
