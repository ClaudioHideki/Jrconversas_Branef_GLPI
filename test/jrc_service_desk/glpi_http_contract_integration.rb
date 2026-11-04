# frozen_string_literal: true

require_relative 'glpi_test_helper'

class GlpiHttpContractTest < GlpiIntegrationTest
  def setup
    super
    @http = ActionDispatch::Integration::Session.new(Rails.application)
    @base = "/api/v1/accounts/#{@account.id}/jrc_service_desk/glpi"
    @headers = @user.create_new_auth_token
  end

  def test_all_new_operational_routes_require_identity_before_remote_io
    routes = [[:post, 'operations'], [:get, 'overview'], [:get, 'search_fields/tickets'],
              [:post, 'exports'], [:get, 'exports/1'], [:post, 'exports/1/cancel'], [:get, 'exports/1/download'],
              [:post, 'sync'], [:get, 'sync'], [:get, 'sync/1'], [:post, 'sync/1/cancel'],
              [:post, 'tickets/1/documents'], [:get, 'tickets/1/documents/2/download']]
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Unbound browser contacted GLPI' }) do
      routes.each do |verb, route|
        @http.public_send(verb, "#{@base}/#{route}", headers: @headers)
        assert_equal 409, @http.response.status, "#{verb} #{route}"
        assert_equal 'configuration_precondition_required', JSON.parse(@http.response.body)['source_code']
      end
    end
  end

  def test_stale_configuration_blocks_colliding_ticket_before_lookup
    old_version = @connection.lock_version
    @connection.update!(categories: [{ id: 1, name: 'Configuration changed', entity_id: 0 }])
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Stale screen contacted GLPI' }) do
      @http.get("#{@base}/tickets/1", headers: @headers.merge('X-JRC-GLPI-Connection-Id' => @connection.id.to_s,
        'X-JRC-GLPI-Connection-Version' => old_version.to_s))
      assert_equal 409, @http.response.status
      assert_equal 'configuration_changed', JSON.parse(@http.response.body)['source_code']
    end
  end

  def test_authenticated_context_and_projection_share_binding_without_source_io
    @connection.update!(primary_source: true)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Projection read contacted GLPI' }) do
      @http.get("/api/v1/accounts/#{@account.id}/jrc_service_desk/ui_context", headers: @headers)
      assert_equal 200, @http.response.status
      context = JSON.parse(@http.response.body)
      assert_equal 'glpi', context['data_source']
      assert_equal @connection.id.to_s, context['connection_id']
      assert_equal @connection.lock_version, context['connection_version']
      @http.get("#{@base}/tickets", headers: @headers.merge('X-JRC-GLPI-Connection-Id' => context['connection_id'],
        'X-JRC-GLPI-Connection-Version' => context['connection_version'].to_s))
      assert_equal 200, @http.response.status
      result = JSON.parse(@http.response.body)
      assert_nil result.dig('meta', 'total')
      assert_equal 'unavailable', result.dig('coverage', 'state')
      assert_equal context['connection_id'], result['connection_id']
      assert_equal context['connection_version'], result['connection_version']
    end
  end

  def test_multipart_document_reaches_dedicated_service_and_returns_receipt
    service = Object.new
    called = false
    account_id = @account.id
    service.define_singleton_method(:upload) do |access:, ticket_id:, file:, idempotency_key:, name:|
      raise 'Wrong account/parent' unless access.context.account.id == account_id && ticket_id == '101'
      raise 'Multipart was not parsed' unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.read == 'synthetic document bytes'
      raise 'Wrong upload metadata' unless name == 'proof.txt' && idempotency_key == 'http-document-proof'

      called = true
      { id: '1', state: 'succeeded' }
    end
    Tempfile.create(['glpi-http-', '.txt']) do |file|
      file.write('synthetic document bytes')
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'text/plain', original_filename: 'proof.txt')
      JrcServiceDesk::Glpi::Documents.stub(:new, service) do
        @http.post("#{@base}/tickets/101/documents", headers: bound_headers,
          params: { file: upload, name: 'proof.txt', idempotency_key: 'http-document-proof' })
      end
    end
    assert called
    assert_equal 201, @http.response.status
    assert_equal 'succeeded', JSON.parse(@http.response.body).dig('command', 'state')
    assert_equal @connection.id.to_s, JSON.parse(@http.response.body)['connection_id']
  end

  def test_document_download_is_authenticated_attachment_without_public_redirect
    source = Object.new
    account_id = @account.id
    source.define_singleton_method(:session) { |&block| block.call(self) }
    service = Object.new
    service.define_singleton_method(:download) do |access:, client:, ticket_id:, document_id:|
      raise 'Wrong download scope' unless access.context.account.id == account_id && client.equal?(source) && ticket_id == '101' && document_id == '7'

      { bytes: 'synthetic document bytes', filename: 'proof.txt', content_type: 'text/plain' }
    end
    JrcServiceDesk::Glpi::Client.stub(:new, source) do
      JrcServiceDesk::Glpi::Documents.stub(:new, service) do
        @http.get("#{@base}/tickets/101/documents/7/download", headers: bound_headers)
      end
    end
    assert_equal 200, @http.response.status
    assert_equal 'synthetic document bytes', @http.response.body
    assert_includes @http.response.headers['Content-Disposition'], 'attachment'
    assert_equal 'nosniff', @http.response.headers['X-Content-Type-Options']
    assert_nil @http.response.headers['Location']
  end

  def test_configuration_change_waits_for_native_account_shared_lock
    worker = nil
    blocked = false
    response_status = nil
    Account.transaction do
      Account.where(id: @account.id).lock('FOR SHARE').take!
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          http = ActionDispatch::Integration::Session.new(Rails.application)
          http.patch("#{@base}/connection", headers: @headers,
            params: { primary_source: true, lock_version: @connection.lock_version }, as: :json)
          response_status = http.response.status
        end
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      while worker.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        blocked = ActiveRecord::Base.connection.select_value(<<~SQL).to_i.positive?
          SELECT count(*) FROM pg_stat_activity
          WHERE datname = current_database() AND pid <> pg_backend_pid()
            AND wait_event_type = 'Lock' AND query LIKE '%FOR UPDATE%'
        SQL
        break if blocked

        sleep 0.02
      end
      refute @connection.reload.primary_source?, 'Configuration must not flip while a native mutation holds its account lock'
    end
    raise 'Configuration request did not finish after lock release' unless worker.join(10)

    worker.value
    assert blocked, 'Configuration update must acquire the exclusive Account lock used against native mutations'
    assert_equal 200, response_status
    assert @connection.reload.primary_source?
  ensure
    worker&.join(10)
  end

  def test_source_namespace_cannot_change_after_a_remote_reference_is_recorded
    JrcServiceDesk::GlpiCommand.create!(account: @account, glpi_connection: @connection, account_user: @member,
      unit: @unit, entity_id: 0, idempotency_key: SecureRandom.uuid, fingerprint: 'namespace-proof', state: 'succeeded',
      operation: 'ticket.update', itemtype: 'Ticket', target_id: 101, remote_id: 101, correlation_id: SecureRandom.uuid)
    @http.patch("#{@base}/connection", headers: @headers,
      params: { base_url: 'https://other-glpi.example.invalid/apirest.php', lock_version: @connection.lock_version }, as: :json)
    assert_equal 409, @http.response.status
    assert_equal 'connection_namespace_locked', JSON.parse(@http.response.body)['source_code']
    assert_equal 'https://glpi.example.invalid/apirest.php', @connection.reload.base_url
  end

  def test_model_namespace_guard_preserves_history_and_allows_equivalent_url_and_token_rotation
    JrcServiceDesk::GlpiTicketSnapshot.create!(account: @account, glpi_connection: @connection, unit: @unit,
      remote_id: 101, entity_id: 0, connection_version: 0, payload: {}, observed_at: Time.current)
    @connection.base_url = 'https://other-glpi.example.invalid/apirest.php'
    refute @connection.valid?
    assert @connection.errors.of_kind?(:base_url, :connection_namespace_locked)
    @connection.base_url = 'https://GLPI.example.invalid:443/apirest.php/'
    @connection.user_token = 'synthetic-replacement-token'
    assert @connection.save
    assert_equal 'synthetic-replacement-token', @connection.reload.user_token
  end

  def test_unused_connection_endpoint_can_be_corrected
    @connection.update!(base_url: 'https://corrected-glpi.example.invalid/apirest.php')
    assert_equal 'https://corrected-glpi.example.invalid/apirest.php', @connection.reload.base_url
  end

  private

  def bound_headers
    @headers.merge('X-JRC-GLPI-Connection-Id' => @connection.id.to_s,
                   'X-JRC-GLPI-Connection-Version' => @connection.lock_version.to_s)
  end
end
