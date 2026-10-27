# frozen_string_literal: true

require 'ssrf_filter'
require 'json'
require 'uri'

class JrcServiceDesk::Glpi::Client
  attr_reader :connection

  def initialize(connection)
    @connection = connection
  end

  def session
    data = request(:get, 'initSession/', auth: true)
    @session_token = data.fetch('session_token')
    yield self
  ensure
    if @session_token
      begin
        request(:get, 'killSession/')
      rescue JrcServiceDesk::Glpi::Error
        Rails.logger.warn('GLPI session cleanup unavailable')
      ensure
        @session_token = nil
      end
    end
  end

  def get(path, parameters = {})
    request(:get, path, parameters: parameters)
  end

  def create_ticket(input)
    request(:post, 'Ticket/', body: { input: input })
  end

  private

  def query_pairs(value, prefix = nil)
    case value
    when Hash then value.flat_map { |key, item| query_pairs(item, prefix ? "#{prefix}[#{key}]" : key.to_s) }
    when Array then value.each_with_index.flat_map { |item, index| query_pairs(item, "#{prefix}[#{index}]") }
    else [[prefix, value.to_s]]
    end
  end

  def request(method, path, parameters: {}, body: nil, auth: false)
    url = "#{connection.base_url.delete_suffix('/')}/#{path}"
    url += "?#{URI.encode_www_form(query_pairs(parameters))}" if parameters.any?
    headers = { 'Content-Type' => 'application/json', 'App-Token' => connection.app_token }
    headers[auth ? 'Authorization' : 'Session-Token'] = auth ? "user_token #{connection.user_token}" : @session_token
    response_body = +''
    status = nil
    SsrfFilter.public_send(method, url, headers: headers, body: body && JSON.generate(body), max_redirects: 0,
                          sensitive_headers: %w[authorization app-token session-token],
                          http_options: { open_timeout: 5, read_timeout: 30 }) do |response|
      status = response.code.to_i
      response.read_body do |chunk|
        response_body << chunk
        raise JrcServiceDesk::Glpi::Error.new('response_too_large') if response_body.bytesize > 8.megabytes
      end
    end
    data = JSON.parse(response_body)
    unless [200, 201, 206].include?(status)
      code = data.is_a?(Array) && data.first.is_a?(String) && data.first.match?(/\AERROR_[A-Z_]+\z/) ? data.first : 'remote_error'
      raise JrcServiceDesk::Glpi::Error.new(code, [401, 403].include?(status) ? 403 : status == 404 ? 404 : 502)
    end
    data
  rescue JSON::ParserError, KeyError
    raise JrcServiceDesk::Glpi::Error.new('invalid_response'), cause: nil
  rescue SsrfFilter::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError, Errno::ECONNRESET, EOFError
    raise JrcServiceDesk::Glpi::Error.new('source_unavailable'), cause: nil
  end
end
