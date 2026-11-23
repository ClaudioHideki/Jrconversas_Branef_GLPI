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
                can_manage: policy.manage?, can_manage_trash: policy.trash?, can_create: policy.create?, can_export: policy.export?,
                user_mapping_required: !access.all_tickets? && access.glpi_user_id.nil? }
    if ready
      with_client do |client|
        entities = client.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
        payload[:entities] = entities.select { |row| access.entity_ids.include?(::JrcServiceDesk::Glpi::Identifiers.remote(row['id'])) }
                                    .map { |row| { id: row['id'], name: ::JrcServiceDesk::Glpi::Normalize.text(row['name']) } }
        payload[:categories] = access.connection.categories.select { |row| access.entity_ids.include?(row['entity_id'].to_i) }
        payload[:requester_id] = access.glpi_user_id
        payload[:timezone] = ActiveSupport::TimeZone[access.connection.timezone].tzinfo.name
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
    raise ArgumentError if values.key?('primary_source') && ![true, false].include?(values['primary_source'])
    connection = nil
    Account.transaction do
      # Native mutations hold this Account FOR SHARE. The exclusive lock also
      # serializes first-connection insertion, where no connection row exists yet.
      Account.where(id: Current.account.id).lock('FOR UPDATE').take!
      fresh = ::JrcServiceDesk::Glpi::Access.new(pundit_user)
      raise Pundit::NotAuthorizedError unless ::JrcServiceDesk::GlpiPolicy.new(fresh.context.to_h, :glpi).manage?

      connection = fresh.connection || ::JrcServiceDesk::GlpiConnection.new(account: fresh.context.account)
      raise ActiveRecord::StaleObjectError if connection.persisted? && values['lock_version'] != connection.lock_version

      values.delete('lock_version')
      %w[user_token app_token].each { |key| values.delete(key) if values[key].blank? }
      connection.assign_attributes(values)
      connection.save!
      audit!('glpi_configuration', connection,
             { enabled: connection.enabled?, credentials_changed: values.key?('user_token') || values.key?('app_token') })
    end
    @glpi_access = nil
    render json: configuration_payload(connection)
  rescue ActiveRecord::RecordInvalid => error
    if error.record.is_a?(::JrcServiceDesk::GlpiConnection) && error.record.errors.of_kind?(:base_url, :connection_namespace_locked)
      raise ::JrcServiceDesk::Glpi::Error.new('connection_namespace_locked', 409)
    end

    raise
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
    result = if access.connection&.primary_source?
               ::JrcServiceDesk::Glpi::Overview.new.list(access: access, filters: request.query_parameters)
             else
               with_client { |client| ::JrcServiceDesk::Glpi::TicketQuery.new(access, request.query_parameters).page(client) }
             end
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

  # Deleted records never enter the operational projection, counts or exports.
  def trash
    permit!(:trash?)
    result = with_client do |client|
      ::JrcServiceDesk::Glpi::TicketQuery.new(access, request.query_parameters, deleted: true).page(client)
    end
    render json: envelope.merge(result).merge(generated_at: Time.current.iso8601)
  end

  def show_trashed_ticket
    permit!(:trash?)
    raise ArgumentError unless request.query_parameters.empty?

    payload = with_client do |client|
      result = ::JrcServiceDesk::Glpi::Detail.new.call(access: access, client: client, ticket_id: ::JrcServiceDesk::Input.id(params[:remote_id]))
      raise ActiveRecord::RecordNotFound unless [1, '1', true].include?(result.fetch(:ticket)['is_deleted'])

      result
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

  def ticket_form
    permit!(:create?)
    form = with_client do |client|
      ::JrcServiceDesk::Glpi::TicketForm.new.call(access: access, client: client, filters: request.query_parameters)
    end
    render json: envelope.merge(form: form)
  end

  def resources
    permit!(:read?)
    result = with_client do |client|
      if params[:kind] == 'asset_candidates'
        ::JrcServiceDesk::Glpi::AssetQuery.new.call(access: access, client: client, filters: request.query_parameters)
      else
        ::JrcServiceDesk::Glpi::ResourceQuery.new.call(access: access, client: client, kind: params[:kind], filters: request.query_parameters)
      end
    end
    render json: envelope.merge(result)
  end

  def resource
    permit!(:read?)
    result = with_client do |client|
      if params[:kind] == 'asset_candidates'
        ::JrcServiceDesk::Glpi::AssetQuery.new.find(access: access, client: client, id: params[:remote_id], filters: request.query_parameters)
      else
        raise ArgumentError unless request.query_parameters.empty?

        ::JrcServiceDesk::Glpi::ResourceQuery.new.find(access: access, client: client, kind: params[:kind], id: params[:remote_id])
      end
    end
    render json: envelope.merge(item: result)
  end

  def relations
    permit!(:read?)
    result = with_client do |client|
      parent = params[:resource_kind].present? ? { 'problems' => 'Problem', 'changes' => 'Change',
                                                  'templates' => 'TicketTemplate' }.fetch(params[:resource_kind]) : 'Ticket'
      ::JrcServiceDesk::Glpi::ResourceQuery.new.related(access: access, client: client, kind: params[:kind],
                                                      ticket_id: params[:remote_id], parent_type: parent)
    end
    render json: envelope.merge(result)
  end

  def search_fields
    permit!(:read?)
    fields = with_client { |client| ::JrcServiceDesk::Glpi::ResourceQuery.new.search_fields(access: access, client: client, kind: params[:kind]) }
    render json: envelope.merge(fields: fields)
  end

  def operate
    permit!(:operate?)
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters,
      %w[operation target_id entity_id attributes idempotency_key expected_version reason template_version])
    receipt = ::JrcServiceDesk::Glpi::Execute.new.call(access: access,
      operation: values.fetch('operation'), target_id: values['target_id'], entity_id: values.fetch('entity_id'),
      attributes: values.fetch('attributes'), idempotency_key: values.fetch('idempotency_key'),
      expected_version: values['expected_version'], reason: values['reason'], template_version: values['template_version'])
    render json: envelope.merge(command: receipt), status: receipt[:state] == 'succeeded' ? :ok : :accepted
  end

  def upload_document
    permit!(:operate?)
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[file name idempotency_key])
    receipt = ::JrcServiceDesk::Glpi::Documents.new.upload(access: access, ticket_id: params[:ticket_id],
      file: values.fetch('file'), idempotency_key: values.fetch('idempotency_key'), name: values['name'])
    render json: envelope.merge(command: receipt), status: receipt[:state] == 'succeeded' ? :created : :accepted
  end

  def download_document
    permit!(:read?)
    result = with_client do |client|
      ::JrcServiceDesk::Glpi::Documents.new.download(access: access, client: client,
        ticket_id: params[:ticket_id], document_id: params[:document_id])
    end
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data result.fetch(:bytes), filename: result.fetch(:filename), type: result.fetch(:content_type), disposition: 'attachment'
  end

  def overview
    permit!(:report?)
    render json: envelope.merge(report: ::JrcServiceDesk::Glpi::Overview.new.call(access: access, filters: request.query_parameters))
  end

  def prepare_export
    permit!(:export?)
    record = ::JrcServiceDesk::Glpi::Export.new.prepare(access: access, filters: request.request_parameters)
    render json: envelope.merge(export: record.receipt), status: :accepted
  end

  def export_status
    permit!(:export?)
    record = ::JrcServiceDesk::Glpi::Export.new.status(access: access, id: params[:export_id])
    render json: envelope.merge(export: record.receipt)
  end

  def cancel_export
    permit!(:export?)
    record = ::JrcServiceDesk::Glpi::Export.new.cancel(access: access, id: params[:export_id])
    render json: envelope.merge(export: record.receipt)
  end

  def download_export
    permit!(:export?)
    record = ::JrcServiceDesk::Glpi::Export.new.download(access: access, id: params[:export_id])
    unless record.state == 'ready'
      return render json: envelope.merge(export: record.receipt), status: record.state == 'verifying' ? :accepted : :conflict
    end

    # The export service consumed a fresh one-use source verification proof.
    # No signed storage URL or unauthenticated redirect is exposed.
    send_data record.artifact.download, filename: 'glpi-tickets.csv', type: 'text/csv; charset=utf-8', disposition: 'attachment'
  end

  def start_sync
    permit!(:manage?)
    run = ::JrcServiceDesk::Glpi::SyncStatus.new.prepare(access: access)
    render json: envelope.merge(sync: run.receipt), status: :accepted
  end

  def sync_status
    permit!(:manage?)
    run = ::JrcServiceDesk::Glpi::SyncStatus.new.status(access: access, id: params[:sync_id])
    render json: envelope.merge(sync: run.receipt)
  end

  def latest_sync
    permit!(:manage?)
    run = ::JrcServiceDesk::Glpi::SyncStatus.new.latest(access: access)
    render json: envelope.merge(sync: run&.receipt)
  end

  def cancel_sync
    permit!(:manage?)
    run = ::JrcServiceDesk::Glpi::SyncStatus.new.cancel(access: access, id: params[:sync_id])
    render json: envelope.merge(sync: run.receipt)
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
    record = ::JrcServiceDesk::GlpiCommand.find_by!(account_id: access.context.account.id, glpi_connection: access.connection,
                                                   id: ::JrcServiceDesk::Input.id(params[:command_id]))
    receipt = ::JrcServiceDesk::Glpi::Reconcile.new.call(access: access, command: record, remote_id: values['remote_id'])
    audit!('glpi_reconciliation', record, { remote_id: receipt[:remote_id] })
    render json: envelope.merge(command: receipt)
  rescue ::JrcServiceDesk::Glpi::Error => error
    # The pre-existing optional connector exposes invalid correlation as 422.
    raise ArgumentError if !access.connection.primary_source? && error.code == 'reconciliation_unverifiable'

    raise
  end

  def report
    permit!(:report?)
    return overview if access.connection&.primary_source?

    rows = with_client { |client| ::JrcServiceDesk::Glpi::TicketQuery.new(access, request.query_parameters).all(client) }
    render json: envelope.merge(report: ::JrcServiceDesk::Glpi::Report.build(rows), filters: request.query_parameters)
  end

  def export
    permit!(:export?)
    if access.connection&.primary_source?
      record = ::JrcServiceDesk::Glpi::Export.new.prepare(access: access, filters: request.query_parameters)
      return render json: envelope.merge(export: record.receipt), status: :accepted
    end

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
    modern = %w[operate capabilities ticket_form trash show_trashed_ticket resources resource relations search_fields upload_document download_document overview
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
