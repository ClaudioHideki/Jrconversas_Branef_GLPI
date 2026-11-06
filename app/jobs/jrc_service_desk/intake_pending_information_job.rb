# frozen_string_literal: true

class JrcServiceDesk::IntakePendingInformationJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(demand_id, generation)
    JrcServiceDesk::Intake::PendingInformation.new.expire(demand_id: demand_id, generation: generation)
  end
end
