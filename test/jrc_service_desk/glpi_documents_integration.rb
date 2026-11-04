# frozen_string_literal: true

require_relative 'glpi_commands_integration'
require 'stringio'

class GlpiDocumentSource < GlpiCommandSource
  attr_accessor :upload_timeout, :link_timeout, :skip_link, :download_hook
  attr_reader :downloads

  def initialize
    super
    @downloads = []
  end

  def upload_document(input, bytes:, filename:, content_type:)
    writes << [:upload, 'Document', nil, input.deep_dup]
    command = JrcServiceDesk::GlpiCommand.where(state: 'sending').last!
    raise 'Missing durable upload stage' unless command.result['stage'] == 'upload_sending'

    rows['Document/601'] = input.merge('id' => 601, 'filename' => filename, 'mime' => content_type)
    raise JrcServiceDesk::Glpi::Error.new('source_unavailable') if upload_timeout

    { 'id' => 601 }
  end

  def create_item(type, input)
    return super unless type == 'Document_Item'

    command = JrcServiceDesk::GlpiCommand.where(state: 'sending').last!
    raise 'Missing durable link stage' unless command.remote_id == 601 && command.result['stage'] == 'link_sending'

    writes << [:post, type, nil, input.deep_dup]
    rows['Document_Item/701'] = input.merge('id' => 701) unless skip_link
    raise JrcServiceDesk::Glpi::Error.new('source_unavailable') if link_timeout

    { 'id' => 701 }
  end

  def get(path, *)
    return { 'active_profile' => { 'document' => 31, 'ticket' => 31 } } if path == 'getActiveProfile/'

    super
  end

  def collection(path, *)
    return rows.values.select { |row| row['documents_id'] && row['items_id'].to_s == path.split('/')[1] } if path.match?(%r{\ATicket/\d+/Document_Item/\z})

    super
  end

  def download_document(id)
    downloads << id
    download_hook&.call
    { bytes: 'SYNTHETIC FILE', content_type: 'text/plain' }
  end
end

class GlpiDocumentsTest < GlpiIntegrationTest
  FileUpload = Struct.new(:tempfile, :original_filename, :content_type)

  def setup
    super
    @remote = GlpiDocumentSource.new
    @documents = JrcServiceDesk::Glpi::Documents.new(client_factory: ->(_) { @remote })
    @access = JrcServiceDesk::Glpi::Access.new(@identity)
    @file = FileUpload.new(StringIO.new('SYNTHETIC FILE'), "../../unsafe\r\nname.txt", 'text/plain')
  end

  def upload(key: 'upload-one', file: @file)
    @documents.upload(access: @access, ticket_id: 101, file: file, name: 'Synthetic attachment', idempotency_key: key)
  end

  def test_upload_confirms_document_and_exact_ticket_link_once_with_safe_filename
    receipt = upload
    assert_equal 'succeeded', receipt[:state], receipt.inspect
    assert_equal '601', receipt[:remote_id]
    assert_equal receipt[:id], upload[:id]
    assert_equal 2, @remote.writes.size
    assert_match(/\A[a-zA-Z0-9_-]+\.txt\z/, @remote.rows['Document/601']['filename'])
    assert_equal 101, @remote.rows['Document_Item/701']['items_id']
    assert_equal 900, receipt[:technical_user_id]
    refute_includes JrcServiceDesk::GlpiCommand.last.request_payload.to_json, 'SYNTHETIC FILE'
  end

  def test_timeout_after_upload_and_link_are_never_resent
    @remote.upload_timeout = true
    receipt = upload
    assert_equal 'indeterminate', receipt[:state]
    assert_equal receipt[:id], upload[:id]
    assert_equal 1, @remote.writes.size
    other_file = FileUpload.new(StringIO.new('DIFFERENT'), 'safe.txt', 'text/plain')
    assert_raises(JrcServiceDesk::IdempotencyConflict) { upload(file: other_file) }
  end

  def test_ambiguous_link_is_reconciled_by_read_proof_without_new_writes
    @remote.link_timeout = true
    receipt = upload
    assert_equal 'indeterminate', receipt[:state]
    reconciled = JrcServiceDesk::Glpi::Reconcile.new(client_factory: ->(_) { @remote }).call(
      access: @access, command: JrcServiceDesk::GlpiCommand.find(receipt[:id]))
    assert_equal 'succeeded', reconciled[:state]
    assert_equal 2, @remote.writes.size
  end

  def test_upload_without_confirmed_link_does_not_claim_success
    @remote.skip_link = true
    assert_equal 'indeterminate', upload[:state]
    assert_equal 601, JrcServiceDesk::GlpiCommand.last.remote_id
  end

  def test_upload_rejects_oversize_without_network_write
    file = FileUpload.new(StringIO.new('a' * (20.megabytes + 1)), 'large.txt', 'text/plain')
    error = assert_raises(JrcServiceDesk::Glpi::Error) { upload(file: file) }
    assert_equal 'upload_too_large', error.code
    assert_empty @remote.writes
  end

  def test_download_requires_exact_link_parent_and_account_scope
    @remote.rows['Document/601'] = { 'id' => 601, 'entities_id' => 0, 'filename' => '../file.txt', 'mime' => 'text/plain' }
    assert_raises(Pundit::NotAuthorizedError) do
      @documents.download(access: @access, client: @remote, ticket_id: 101, document_id: 601)
    end
    @remote.rows['Document_Item/701'] = { 'id' => 701, 'documents_id' => 601, 'items_id' => 101, 'itemtype' => 'Ticket' }
    result = @documents.download(access: @access, client: @remote, ticket_id: 101, document_id: 601)
    assert_equal 'SYNTHETIC FILE', result[:bytes]
    refute_match(/[\/\\\r\n]/, result[:filename])
    @remote.rows['Ticket/101']['entities_id'] = 999
    assert_raises(Pundit::NotAuthorizedError) do
      @documents.download(access: @access, client: @remote, ticket_id: 101, document_id: 601)
    end
    assert_equal [601], @remote.downloads
  end

  def test_generic_json_executor_cannot_upload_a_document
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::Execute.new.call(access: @access, operation: 'document.upload', target_id: nil,
        entity_id: 0, attributes: { 'parent_id' => 101 }, idempotency_key: 'json')
    end
    assert_equal 'multipart_required', error.code
    assert_empty @remote.writes
  end
end
