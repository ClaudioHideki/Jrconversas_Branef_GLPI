# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::GlpiController < Api::V1::Accounts::JrcServiceDesk::BaseController
  wrap_parameters false
  before_action { response.headers['Cache-Control'] = 'no-store' }
  before_action :verify_connection_binding!, except: %i[context configuration update_configuration validate_connection]
  rescue_from ::JrcServiceDesk::Glpi::Error, with: :source_error
  rescue_from ArgumentError, KeyError, ActionController::ParameterMissing, with: :invalid_input
  rescue_from ::JrcServiceDesk::IdempotencyConflict, ActiveRecord::StaleObjectError, with: :conflict

  def context
    permit!(:read?)
    ready = access.connection&.enabled? && access.mappings.any? && (access.all_tickets? || access.glpi_user_id.present?)
    payload = { configured: access.connection.present?, enabled: access.connection&.enabled? == true, available: ready == true,
                can_manage: policy.manage?, can_create: policy.create?, can_export: policy.export?,
                user_mapping_required: !access.all_tickets? && access.glpi_user_id.nil? }
    if ready
      with_client do |client|
        entities = client.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
        payload[:entities] = entities.select { |row| access.entity_ids.include?(::JrcServiceDesk::Glpi::Identifiers.remote(row['id'])) }
                                    .map { |row| { id: row['id'], name: ::JrcServiceDesk::Glpi::Normalize.text(row['name']) } }
        payload[:categories] = access.connection.categories.select { |row| access.entity_ids.include?(row['entity_id'].to_i) }
        payload[:requester_id] = access.glpi_user_id
        payload[:timezone] = access.connection.timezone
      end
    end
    render json: envelope.merge(payload)
  end

  def configuration
    permit!(:manage?)
    connection = access.connection || ::JrcServiceDesk::GlpiConnection.new(timezone: 'America/Sao_Paulo')
    render json: configuration_payload(connection)
  end

  def update_configuration
    permit!(:manage?)
    allowed = %w[base_url user_token app_token enabled primary_source timezone entity_mappings user_mappings categories lock_version]
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, allowed)
    connection = access.connection || ::JrcServiceDesk::GlpiConnection.new(account: access.context.account)
    raise ActiveRecord::StaleObjectError if connection.persisted? && values['lock_version'] != connection.lock_version

    values.delete('lock_version')
    %w[user_token app_token].each { |key| values.delete(key) if values[key].blank? }
    connection.assign_attributes(values)
    connection.save!
    audit!('glpi_configuration', connection,
           { enabled: connection.enabled?, credentials_changed: values.key?('user_token') || values.key?('app_token') })
    render json: configuration_payload(connection)
  end

  def validate_connection
    permit!(:manage?)
    connection = access.connection || raise(::JrcServiceDesk::Glpi::Error.new('not_configured', 422))
    result = {}
    ::JrcServiceDesk::Glpi::Client.new(connection).session do |client|
      profile = client.get('getActiveProfile/').fetch('active_profile')
      entities = client.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
      options = client.get('listSearchOptions/Ticket/')
      required = (::JrcServiceDesk::Glpi::Normalize::FIELDS.keys + %w[4]).all? { |key| options[key].is_a?(Hash) }
      raise ::JrcServiceDesk::Glpi::Error.new('unsupported_search_fields', 422) unless required

      result = { connected: true, profile: profile.slice('id', 'name'), can_create: (profile.fetch('ticket', 0).to_i & 4).positive?,
                 can_read_all: (profile.fetch('ticket', 0).to_i & 1024).positive?,
                 entities: entities.map { |row| { id: row['id'], name: ::JrcServiceDesk::Glpi::Normalize.text(row['name']) } } }
    end
    render json: envelope.merge(result)
  end

  def tickets
    permit!(:read?)
    result = with_client { |client| ::JrcServiceDesk::Glpi::TicketQuery.new(access, request.query_parameters).page(client) }
    render json: envelope.merge(result).merge(generated_at: Time.current.iso8601)
  end

  def show_ticket
    permit!(:read?)
    id = ::JrcServiceDesk::Input.id(params[:remote_id])
    payload = with_client do |client|
      ::JrcServiceDesk::Glpi::Detail.new.call(access: access, client: client, ticket_id: id)
    end
    render json: envelope.merge(payload)
  end

  def create_ticket
    permit!(:create?)
    receipt = ::JrcServiceDesk::Glpi::CreateTicket.new(access).call(request.request_parameters)
    render json: envelope.merge(command: receipt), status: receipt[:state] == 'succeeded' ? :created : :accepted
  end

  def capabilities
    permit!(:read?)
    result = with_client { |client| ::JrcServiceDesk::Glpi::Capabilities.new.call(access: access, client: client) }
    render json: envelope.merge(result)
  end

  def resources
    permit!(:read?)
    result = with_client do |client|
      ::JrcServiceDesk::Glpi::ResourceQuery.new.call(access: access, client: client, kind: params[:kind], filters: request.query_parameters)
    end
    render json: envelope.merge(result)
  end

  def resource
    permit!(:read?)
    result = with_client do |client|
      ::JrcServiceDesk::Glpi::ResourceQuery.new.find(access: access, client: client, kind: params[:kind], id: params[:remote_id])
    end
    render json: envelope.merge(item: result)
  end

  def relations
    permit!(:read?)
    result = with_client do |client|
      parent = params[:resource_kind].present? ? { 'problems' => 'Problem', 'changes' => 'Change' }.fetch(params[:resource_kind]) : 'Ticket'
      ::JrcServiceDesk::Glpi::ResourceQuery.new.related(access: access, client: client, kind: params[:kind],
                                                      ticket_id: params[:remote_id], parent_type: parent)
    end
    render json: envelope.merge(result)
  end

  def command
    permit!(:read?)
    access.ready!
    record = ::JrcServiceDesk::GlpiCommand.find_by!(account_id: access.context.account.id, glpi_connection: access.connection,
                                                   account_user: access.context.account_user, id: ::JrcServiceDesk::Input.id(params[:command_id]))
    access.unit_for(record.entity_id)
    render json: envelope.merge(command: record.receipt)
  end

  def lookup_command
    permit!(:read?)
    access.ready!
    values = ::JrcServiceDesk::Input.attributes(request.query_parameters, %w[idempotency_key])
    key = ::JrcServiceDesk::Input.request_key(values.fetch('idempotency_key'))
    record = ::JrcServiceDesk::GlpiCommand.find_by!(account_id: access.context.account.id, glpi_connection: access.connection,
                                                   account_user: access.context.account_user, idempotency_key: key)
    access.unit_for(record.entity_id)
    render json: envelope.merge(command: record.receipt)
  end

  def reconcile_command
    permit!(:manage?)
    access.ready!
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[remote_id])
    remote_id = ::JrcServiceDesk::Input.id(values.fetch('remote_id'))
    record = ::JrcServiceDesk::GlpiCommand.find_by!(account_id: access.context.account.id, glpi_connection: access.connection,
                                                   id: ::JrcServiceDesk::Input.id(params[:command_id]))
    access.unit_for(record.entity_id)
    ticket = with_client { |client| client.get("Ticket/#{remote_id}") }
    unless ticket['entities_id'].to_s == record.entity_id.to_s &&
           ::JrcServiceDesk::Glpi::Normalize.text(ticket['content']).include?(record.correlation_marker)
      raise ArgumentError
    end
    record.with_lock do
      raise ::JrcServiceDesk::IdempotencyConflict unless %w[sending indeterminate].include?(record.state)

      record.update!(state: 'succeeded', remote_id: remote_id, error_code: nil)
    end
    audit!('glpi_reconciliation', record, { remote_id: remote_id })
    render json: envelope.merge(command: record.receipt)
  end

  def report
    permit!(:report?)
    rows = with_client { |client| ::JrcServiceDesk::Glpi::TicketQuery.new(access, request.query_parameters).all(client) }
    render json: envelope.merge(report: ::JrcServiceDesk::Glpi::Report.build(rows), filters: request.query_parameters)
  end

  def export
    permit!(:export?)
    rows = with_client { |client| ::JrcServiceDesk::Glpi::TicketQuery.new(access, request.query_parameters).all(client) }
    fields = ::JrcServiceDesk::Glpi::Normalize::FIELDS.values
    csv = ::JrcServiceDesk::OperationalCsv.generate(fields, rows.map { |row| fields.map { |key| row[key] } })
    audit!('glpi_export', access.connection,
           { filters: request.query_parameters, count: rows.size, sha256: Digest::SHA256.hexdigest(csv) })
    send_data csv, filename: 'glpi-tickets.csv', type: 'text/csv; charset=utf-8', disposition: 'attachment'
  end

  private

  def policy
    @glpi_policy ||= ::JrcServiceDesk::GlpiPolicy.new(pundit_user, :glpi)
  end

  def permit!(action)
    authorize :glpi, action, policy_class: ::JrcServiceDesk::GlpiPolicy
  end

  def access
    @glpi_access ||= ::JrcServiceDesk::Glpi::Access.new(pundit_user)
  end

  def envelope
    { contract_version: 1, account_id: Current.account.id.to_s, user_id: access.context.user.id.to_s, source: 'glpi' }.tap do |payload|
      connection = access.connection
      payload.merge!(connection_id: connection.id.to_s, connection_version: connection.lock_version) if connection
    end
  end

  def verify_connection_binding!
    modern = %w[operate capabilities resources resource relations search_fields upload_document download_document overview
                prepare_export export_status cancel_export download_export start_sync sync_status latest_sync cancel_sync]
    ::JrcServiceDesk::Glpi::ReferenceBinding.verify!(
      access: access, connection_id: request.headers['X-JRC-GLPI-Connection-Id'],
      connection_version: request.headers['X-JRC-GLPI-Connection-Version'],
      required: modern.include?(action_name) || access.connection&.primary_source? == true
    )
  end

  def with_client(&block)
    access.ready!
    ::JrcServiceDesk::Glpi::Client.new(access.connection).session(&block)
  end

  def configuration_payload(connection)
    envelope.merge(connection: connection.public_configuration,
                   units: access.context.unit_scope.map { |unit| { id: unit.id, name: unit.name } },
                   members: AccountUser.where(account_id: Current.account.id).includes(:user).map do |member|
                     { id: member.id, name: member.user.name }
                   end)
  end

  def audit!(action, record, metadata)
    Audited::Audit.create!(auditable: record, user: access.context.user, action: action, audited_changes: {},
                           comment: ::JrcServiceDesk::CanonicalJson.dump(metadata.merge(account_id: Current.account.id)), request_uuid: SecureRandom.uuid)
  end

  def source_error(error)
    render json: { code: 'glpi_source_error', source_code: error.code }, status: error.http_status
  end

  def render_unauthorized(_message)
    render json: { code: 'forbidden' }, status: :forbidden
  end

  def render_not_found_error(_message)
    render json: { code: 'not_found' }, status: :not_found
  end

  def invalid_input(_error)
    render json: { code: 'invalid_input' }, status: :unprocessable_entity
  end

  def conflict(_error)
    render json: { code: 'conflict' }, status: :conflict
  end
end
