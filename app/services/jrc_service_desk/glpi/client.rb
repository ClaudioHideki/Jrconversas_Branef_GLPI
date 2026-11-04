# frozen_string_literal: true

require 'ssrf_filter'
require 'json'
require 'uri'
require 'securerandom'
require_relative 'collection'

class JrcServiceDesk::Glpi::Client
  MUTABLE_TYPES = %w[Ticket TicketTask ITILFollowup ITILSolution TicketValidation Document Document_Item
                     Ticket_User Group_Ticket Supplier_Ticket Item_Ticket Problem Change Problem_Ticket Change_Ticket
                     ProblemTask ChangeTask ProblemValidation ChangeValidation Problem_User Group_Problem Change_User Change_Group
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
    if connection.respond_to?(:primary_source?) && connection.primary_source?
      # Omitting entities_id is GLPI 10's supported "all permitted" selection;
      # the literal string "all" is cast to root 0 by that version's REST API.
      # This changes only this short-lived session, never the user's profile.
      selected = request(:post, 'changeActiveEntities/', body: { 'is_recursive' => true })
      raise JrcServiceDesk::Glpi::Error.new('entity_selection_failed', 403) if selected == false
      raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless selected == true
    end
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

  # Binary transport is deliberately restricted to the official Document endpoint.
  def upload_document(input, bytes:, filename:, content_type:)
    raise ArgumentError unless filename.match?(/\A[A-Za-z0-9_-]+(?:\.[A-Za-z0-9]{1,12})?\z/)
    raise ArgumentError unless content_type.match?(/\A[a-zA-Z0-9!#$&^_.+-]+\/[a-zA-Z0-9!#$&^_.+-]+\z/)
    raise JrcServiceDesk::Glpi::Error.new('upload_too_large', 413) if bytes.bytesize > 20.megabytes

    boundary = "JRC#{SecureRandom.hex(24)}"
    manifest = JSON.generate(input: input.merge('_filename' => [filename]))
    body = +"--#{boundary}\r\nContent-Disposition: form-data; name=\"uploadManifest\"\r\nContent-Type: application/json\r\n\r\n#{manifest}\r\n"
    body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"filename[0]\"; filename=\"#{filename}\"\r\nContent-Type: #{content_type}\r\n\r\n"
    body = body.b << bytes.b << "\r\n--#{boundary}--\r\n"
    request(:post, 'Document/', encoded_body: body, extra_headers: { 'Content-Type' => "multipart/form-data; boundary=#{boundary}" })
  end

  def download_document(id)
    request(:get, "Document/#{item_id!(id)}", extra_headers: { 'Accept' => 'application/octet-stream' }, binary: true)
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

  def request(method, path, parameters: {}, body: nil, auth: false, encoded_body: nil, extra_headers: {}, binary: false)
    raise ArgumentError unless path.is_a?(String) && path.match?(/\A[A-Za-z][A-Za-z0-9_]*(?:\/[A-Za-z0-9_]+)*\/?\z/)

    url = "#{connection.base_url.delete_suffix('/')}/#{path}"
    url += "?#{URI.encode_www_form(query_pairs(parameters))}" if parameters.any?
    headers = { 'Content-Type' => 'application/json', 'App-Token' => connection.app_token }
    headers[auth ? 'Authorization' : 'Session-Token'] = auth ? "user_token #{connection.user_token}" : @session_token
    headers.merge!(extra_headers)
    response_body = +''.b
    status = nil
    content_type = nil
    SsrfFilter.public_send(method, url, headers: headers, body: encoded_body || (body && JSON.generate(body)), max_redirects: 0,
                          sensitive_headers: %w[authorization app-token session-token],
                          http_options: { open_timeout: 5, read_timeout: 30 }) do |response|
      status = response.code.to_i
      content_type = response['content-type']
      @last_response = { status: status, content_range: response['content-range'], accept_range: response['accept-range'] }.freeze
      limit = binary && status == 200 ? 50.megabytes : 8.megabytes
      too_large = binary && status == 200 ? 'download_too_large' : 'response_too_large'
      length = response['content-length']
      raise JrcServiceDesk::Glpi::Error.new(too_large, 413) if length && length.to_i > limit
      response.read_body do |chunk|
        raise JrcServiceDesk::Glpi::Error.new(too_large, 413) if response_body.bytesize + chunk.bytesize > limit

        response_body << chunk
      end
      if binary && status == 200 && length && length.to_i != response_body.bytesize
        raise JrcServiceDesk::Glpi::Error.new('incomplete_download')
      end
    end
    return { bytes: response_body, content_type: content_type } if binary && status == 200
    raise JrcServiceDesk::Glpi::Error.new('incomplete_download') if binary && [204, 206].include?(status)
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
