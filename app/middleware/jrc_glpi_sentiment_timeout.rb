# frozen_string_literal: true

require 'rack-timeout'

# Native inference has its own 75-second deadline. Keep the normal Rack budget
# everywhere else, without changing a shared timeout instance during a request.
class JrcGlpiSentimentTimeout
  PATH = %r{\A/api/v1/accounts/[1-9]\d*/jrc_service_desk/glpi/tickets/[1-9]\d*/sentiment\z}

  def initialize(app)
    @ordinary = Rack::Timeout.new(app)
    @sentiment = Rack::Timeout.new(app, service_timeout: 100, service_past_wait: true)
  end

  def call(env)
    middleware = env['REQUEST_METHOD'] == 'POST' && PATH.match?(env['PATH_INFO'].to_s) ? @sentiment : @ordinary
    middleware.call(env)
  end
end
