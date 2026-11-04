# frozen_string_literal: true

require 'ssrf_filter'
require 'json'
require 'uri'
require_relative 'collection'

class JrcServiceDesk::Glpi::Client
  MUTABLE_TYPES = %w[Ticket TicketTask ITILFollowup ITILSolution TicketValidation Document Document_Item
                     Ticket_User Group_Ticket Supplier_Ticket Item_Ticket Problem Change Problem_Ticket Change_Ticket
                     ProblemTask ChangeTask ProblemValidation ChangeValidation Problem_User Problem_Group Change_User Change_Group
                     KnowbaseItem KnowbaseItem_Item ITILCategory TicketTemplate TicketTemplateMandatoryField
                     TicketTemplateHiddenField TicketTemplatePredefinedField].freeze
  attr_reader :connection, :last_response

  def initialize(connection)
    @connection = connection
    @last_response = {}.freeze
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
    result = create_item('Ticket', input)
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless result.is_a?(Hash)

    result
  end

  def collection(path, parameters = {}, batch_size: 200)
    JrcServiceDesk::Glpi::Collection.new(self, path, parameters, batch_size: batch_size).each
  end

  def create_item(type, input)
    mutable_type!(type)
    request(:post, "#{type}/", body: { input: input })
  end

  def update_item(type, id, input)
    mutable_type!(type)
    id = item_id!(id)
    request(:patch, "#{type}/#{id}", body: { input: input.merge('id' => id) })
  end

  def delete_item(type, id, purge: false)
    mutable_type!(type)
    id = item_id!(id)
    raise ArgumentError unless [true, false].include?(purge)

    result = request(:delete, "#{type}/#{id}", body: { input: { id: id }, force_purge: purge })
    last_response[:status] == 204 ? { 'id' => id, 'deleted' => true } : result
  end

  private

  def mutable_type!(type)
    raise ArgumentError unless MUTABLE_TYPES.include?(type)
  end

  def item_id!(id)
    raise ArgumentError unless id.to_s.match?(/\A[1-9]\d*\z/)

    id.to_i
  end

  def query_pairs(value, prefix = nil)
    case value
    when Hash then value.flat_map { |key, item| query_pairs(item, prefix ? "#{prefix}[#{key}]" : key.to_s) }
    when Array then value.each_with_index.flat_map { |item, index| query_pairs(item, "#{prefix}[#{index}]") }
    else [[prefix, value.to_s]]
    end
  end

  def request(method, path, parameters: {}, body: nil, auth: false)
    raise ArgumentError unless path.is_a?(String) && path.match?(/\A[A-Za-z][A-Za-z0-9_]*(?:\/[A-Za-z0-9_]+)*\/?\z/)

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
      @last_response = { status: status, content_range: response['content-range'], accept_range: response['accept-range'] }.freeze
      response.read_body do |chunk|
        response_body << chunk
        raise JrcServiceDesk::Glpi::Error.new('response_too_large') if response_body.bytesize > 8.megabytes
      end
    end
    return nil if status == 204

    data = JSON.parse(response_body)
    unless [200, 201, 206, 207].include?(status)
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
