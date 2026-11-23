# frozen_string_literal: true

class JrcServiceDesk::Glpi::CockpitMetrics
  def self.call(account:, user:, account_user:, period:)
    context = JrcServiceDesk::OperationalContext.new(account: account, user: user, account_user: account_user)
    return nil unless context.available?

    connection = JrcServiceDesk::GlpiConnection.find_by(account_id: context.account.id, enabled: true, primary_source: true)
    return nil unless connection

    new(context, connection, period).perform
  end

  def initialize(context, connection, period)
    @context = context
    @zone = ActiveSupport::TimeZone[connection.timezone]
    today = Time.current.in_time_zone(@zone).to_date
    days = { '7_days' => 6, '30_days' => 29 }.fetch(period, 0)
    @filters = { 'from' => (today - days).iso8601, 'to' => today.iso8601 }
  end

  def perform
    access = JrcServiceDesk::Glpi::Access.new(@context.to_h).ready!
    report = JrcServiceDesk::Glpi::Overview.new.call(access: access, filters: @filters)
    base.merge(state: report[:coverage][:state], coverage: report[:coverage],
               collected_at: report[:coverage][:collected_at]).merge(counts(report))
  rescue Pundit::NotAuthorizedError
    base.merge(state: 'forbidden')
  rescue JrcServiceDesk::Glpi::Error
    base
  end

  private

  def base
    { source: 'GLPI', state: 'unavailable', total: nil, active: nil, exceeded: nil,
      filters: @filters, route_name: 'jrc_service_desk_glpi', timezone: @zone.tzinfo.name, collected_at: nil }
  end

  def counts(report)
    return { total: nil, active: nil, exceeded: nil } if report[:total].nil?

    active = report[:by_status].sum { |status, count| (1..4).cover?(status.to_i) ? count : 0 }
    { total: report[:total], active: active, exceeded: report[:solution_sla][:exceeded] }
  end
end
