# frozen_string_literal: true

module JrcServiceDesk::Intake::LifecycleLock
  module_function

  def call(demand_id)
    key = Digest::SHA256.hexdigest("service-desk-intake-lifecycle/#{JrcServiceDesk::Input.id(demand_id)}")[0, 15].to_i(16)
    JrcServiceDesk::IntakeDemand.connection_pool.with_connection do |connection|
      connection.execute("SELECT pg_advisory_lock(#{key})")
      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
