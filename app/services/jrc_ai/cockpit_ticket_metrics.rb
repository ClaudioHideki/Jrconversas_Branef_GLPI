# frozen_string_literal: true

# Optional product extension. The core has no dependency on a ticket source.
class JrcAi::CockpitTicketMetrics
  def self.call(account:, user:, account_user:, period:)
    provider = Rails.configuration.x[:jrc_cockpit_ticket_metrics_provider]
    return nil if provider.blank?

    provider.constantize.call(account: account, user: user, account_user: account_user, period: period)
  end
end
