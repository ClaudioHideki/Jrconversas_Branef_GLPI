# frozen_string_literal: true

class JrcServiceDesk::IntakeConfigurationJob < ApplicationJob
  queue_as :low

  def perform(account_id, user_id, operation_id)
    JrcServiceDesk::Intake::ConfigurationOperation.new(account_id, user_id, operation_id).perform
  end
end
