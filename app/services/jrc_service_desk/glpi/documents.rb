# frozen_string_literal: true

require 'digest'
require 'securerandom'

class JrcServiceDesk::Glpi::Documents
  UPLOAD_LIMIT = 20.megabytes
  DOWNLOAD_LIMIT = 50.megabytes

  def initialize(client_factory: ->(connection) { JrcServiceDesk::Glpi::Client.new(connection) })
    @client_factory = client_factory
    @executor = JrcServiceDesk::Glpi::Execute.new(client_factory: client_factory)
  end

  def download(access:, client:, ticket_id:, document_id:)
    ticket_id = JrcServiceDesk::Input.id(ticket_id)
    document_id = JrcServiceDesk::Input.id(document_id)
    access = @executor.fresh_access(access)
    document = authorize_download!(access, client, ticket_id, document_id)
    result = client.download_document(document_id)
    raise JrcServiceDesk::Glpi::Error.new('download_too_large', 413) if result.fetch(:bytes).bytesize > DOWNLOAD_LIMIT

    # Recheck revocation and the association before releasing the buffered file.
    access = @executor.fresh_access(access)
    authorize_download!(access, client, ticket_id, document_id)
    { bytes: result.fetch(:bytes), filename: safe_name(document['filename'].presence || document['name'].presence || "document-#{document_id}"),
      content_type: safe_mime(result[:content_type]) }
  end

  def upload(access:, ticket_id:, file:, idempotency_key:, name: nil)
    ticket_id = JrcServiceDesk::Input.id(ticket_id)
    access = @executor.fresh_access(access)
    descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch('document.upload')
    @executor.authorize_local!(access, descriptor)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    raise ArgumentError unless io.respond_to?(:read) && io.respond_to?(:rewind)

    io.rewind
    bytes = io.read(UPLOAD_LIMIT + 1)
    io.rewind
    raise ArgumentError unless bytes.is_a?(String) && bytes.bytesize.positive?
    raise JrcServiceDesk::Glpi::Error.new('upload_too_large', 413) if bytes.bytesize > UPLOAD_LIMIT

    original_name = safe_name(file.respond_to?(:original_filename) ? file.original_filename : 'attachment')
    title = safe_name(name.presence || original_name)
    mime = safe_mime(file.respond_to?(:content_type) ? file.content_type : nil)
    payload = { 'name' => title, 'original_filename' => original_name, 'mime' => mime, 'size' => bytes.bytesize,
      'sha256' => Digest::SHA256.hexdigest(bytes), 'sha1' => Digest::SHA1.hexdigest(bytes) }
    fingerprint = JrcServiceDesk::CanonicalJson.digest(operation: 'document.upload', parent_id: ticket_id,
      input: payload, connection_version: access.connection.lock_version)
    scope = JrcServiceDesk::GlpiCommand.where(account_id: access.context.account.id, glpi_connection: access.connection,
      account_user: access.context.account_user)
    if (existing = scope.find_by(idempotency_key: key))
      raise JrcServiceDesk::IdempotencyConflict unless existing.fingerprint == fingerprint

      access.unit_for(existing.entity_id)
      return existing.receipt
    end
    raise JrcServiceDesk::Glpi::Error.new('durable_intent_requires_commit', 422) if JrcServiceDesk::GlpiCommand.connection.transaction_open?

    ticket = nil
    @client_factory.call(access.connection).session { |client| ticket = authorized_ticket!(access, client, ticket_id) }
    entity_id = JrcServiceDesk::Glpi::Identifiers.remote(ticket.fetch('entities_id'))
    extension = File.extname(original_name).downcase
    extension = '' unless extension.match?(/\A\.[a-z0-9]{1,12}\z/)
    payload['upload_filename'] = "jrc_#{SecureRandom.hex(16)}#{extension}"
    command = scope.create!(unit_id: access.unit_for(entity_id), entity_id: entity_id, idempotency_key: key,
      fingerprint: fingerprint, operation: 'document.upload', itemtype: 'Document', parent_type: 'Ticket', parent_id: ticket_id,
      connection_version: access.connection.lock_version, request_payload: payload, correlation_id: SecureRandom.uuid,
      result: { 'stage' => 'prepared' })
    @executor.with_object_lock(command) { perform_upload(command, access, bytes, descriptor) }
    command.reload.receipt
  rescue ActiveRecord::RecordNotUnique
    existing = scope.find_by!(idempotency_key: key)
    raise JrcServiceDesk::IdempotencyConflict unless existing.fingerprint == fingerprint

    access.unit_for(existing.entity_id)
    existing.receipt
  end

  # Called by the generic reconciler only after its account/operator authorization.
  # Never sends an upload or association, even when one is absent.
  def reconcile(access:, command:, remote_id: nil)
    @executor.with_object_lock(command) do
      command.reload
      return command.receipt if command.state == 'succeeded'
      raise JrcServiceDesk::IdempotencyConflict unless %w[sending indeterminate].include?(command.state)

      access = @executor.fresh_access(access, command.connection_version)
      @executor.authorize_local!(access, JrcServiceDesk::Glpi::OperationCatalogue.fetch('document.upload'))
      id = JrcServiceDesk::Input.id(command.remote_id || remote_id)
      raise ArgumentError if remote_id && command.remote_id && remote_id.to_s != command.remote_id.to_s

      @client_factory.call(access.connection).session do |client|
        ticket = authorized_ticket!(access, client, command.parent_id)
        @executor.verify_entity!(ticket, command.entity_id)
        document = client.get("Document/#{id}")
        @executor.verify_id!(document, id)
        @executor.verify_entity!(document, command.entity_id)
        if !command.remote_id && (document['sha1sum'] != command.request_payload['sha1'] ||
            !document['comment'].to_s.include?(command.correlation_marker))
          raise JrcServiceDesk::Glpi::Error.new('reconciliation_unverifiable', 409)
        end
        link = exact_link(client, command.parent_id, id)
        raise JrcServiceDesk::Glpi::Error.new('reconciliation_unverifiable', 409) unless link

        access = @executor.fresh_access(access, command.connection_version)
        ticket = authorized_ticket!(access, client, command.parent_id)
        @executor.verify_entity!(ticket, command.entity_id)
        command.update!(state: 'succeeded', remote_id: id, error_code: nil,
          result: { 'stage' => 'linked', 'verified' => true, 'document_id' => id.to_s, 'link_id' => link.fetch('id').to_s })
      end
    end
    command.receipt
  end

  private

  def perform_upload(command, access, bytes, descriptor)
    sent = false
    @client_factory.call(access.connection).session do |client|
      access = @executor.fresh_access(access, command.connection_version)
      @executor.authorize_local!(access, descriptor)
      unresolved!(command)
      ticket = authorized_ticket!(access, client, command.parent_id)
      @executor.verify_entity!(ticket, command.entity_id)
      profile = client.get('getActiveProfile/').fetch('active_profile')
      raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) if (profile.fetch('document', 0).to_i & 4).zero?

      technical_id = JrcServiceDesk::Input.id(client.get('getFullSession/').fetch('session').fetch('glpiID'))
      command.update!(technical_user_id: technical_id, state: 'sending', result: { 'stage' => 'upload_sending' })
      access = @executor.fresh_access(access, command.connection_version)
      @executor.authorize_local!(access, descriptor)
      access.unit_for(command.entity_id)
      payload = command.request_payload
      sent = true
      response = client.upload_document({ 'name' => payload.fetch('name'), 'entities_id' => command.entity_id,
        'comment' => command.correlation_marker }, bytes: bytes, filename: payload.fetch('upload_filename'), content_type: payload.fetch('mime'))
      id = JrcServiceDesk::Input.id(response.fetch('id'))
      command.update!(remote_id: id, result: { 'stage' => 'document_created', 'document_id' => id.to_s })
      document = client.get("Document/#{id}")
      @executor.verify_id!(document, id)
      @executor.verify_entity!(document, command.entity_id)
      access = @executor.fresh_access(access, command.connection_version)
      @executor.authorize_local!(access, descriptor)
      ticket = authorized_ticket!(access, client, command.parent_id)
      @executor.verify_entity!(ticket, command.entity_id)
      # GLPI may deduplicate a file; confirm any existing exact link before adding one.
      link = exact_link(client, command.parent_id, id)
      unless link
        command.update!(result: { 'stage' => 'link_sending', 'document_id' => id.to_s })
        access = @executor.fresh_access(access, command.connection_version)
        @executor.authorize_local!(access, descriptor)
        access.unit_for(command.entity_id)
        client.create_item('Document_Item', { 'documents_id' => id, 'itemtype' => 'Ticket', 'items_id' => command.parent_id })
        link = exact_link(client, command.parent_id, id)
      end
      raise JrcServiceDesk::Glpi::Error.new('write_not_confirmed') unless link

      access = @executor.fresh_access(access, command.connection_version)
      @executor.authorize_local!(access, descriptor)
      ticket = authorized_ticket!(access, client, command.parent_id)
      @executor.verify_entity!(ticket, command.entity_id)
      command.update!(state: 'succeeded', error_code: nil,
        result: { 'stage' => 'linked', 'verified' => true, 'document_id' => id.to_s, 'link_id' => link.fetch('id').to_s })
    end
  rescue Pundit::NotAuthorizedError
    command.update!(state: sent ? 'indeterminate' : 'rejected', error_code: 'not_authorized')
  rescue JrcServiceDesk::Glpi::Error => error
    definitive = !sent || (!command.remote_id && error.http_status == 403)
    command.update!(state: definitive ? 'rejected' : 'indeterminate', error_code: error.code)
  rescue KeyError, ArgumentError, TypeError
    command.update!(state: sent ? 'indeterminate' : 'rejected', error_code: 'invalid_response')
  end

  def unresolved!(command)
    scope = JrcServiceDesk::GlpiCommand.where(glpi_connection_id: command.glpi_connection_id, state: %w[sending indeterminate]).where.not(id: command.id)
    scope = scope.where(parent_type: 'Ticket', parent_id: command.parent_id).or(scope.where(itemtype: 'Ticket', target_id: command.parent_id))
    raise JrcServiceDesk::Glpi::Error.new('unresolved_previous_command', 409) if scope.exists?
  end

  def authorized_ticket!(access, client, id)
    JrcServiceDesk::Glpi::ResourceQuery.new.raw(access: access, client: client, kind: 'tickets', id: id)
  end

  def exact_link(client, ticket_id, document_id)
    client.collection("Ticket/#{ticket_id}/Document_Item/").find do |link|
      link['itemtype'] == 'Ticket' && link['items_id'].to_s == ticket_id.to_s && link['documents_id'].to_s == document_id.to_s &&
        link['id'].to_s.match?(/\A[1-9]\d*\z/)
    end
  end

  def authorize_download!(access, client, ticket_id, document_id)
    authorized_ticket!(access, client, ticket_id)
    raise Pundit::NotAuthorizedError unless exact_link(client, ticket_id, document_id)

    document = client.get("Document/#{document_id}")
    @executor.verify_id!(document, document_id)
    access.unit_for(JrcServiceDesk::Glpi::Identifiers.remote(document.fetch('entities_id')))
    document
  end

  def safe_name(value)
    value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').tr('\\', '/').split('/').last.to_s
      .gsub(/[\x00-\x1f\x7f]/, '').gsub(/[<>:"|?*]/, '_').strip.first(255).presence || 'attachment'
  end

  def safe_mime(value)
    value.to_s.match?(/\A[a-zA-Z0-9!#$&^_.+-]+\/[a-zA-Z0-9!#$&^_.+-]+\z/) ? value : 'application/octet-stream'
  end
end
