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
    routes = [[:post, 'operations'], [:get, 'overview'], [:get, 'search-fields/tickets'],
              [:post, 'exports'], [:get, 'exports/1'], [:post, 'exports/1/cancel'], [:get, 'exports/1/download'],
              [:post, 'sync'], [:get, 'sync/latest'], [:get, 'sync/1'], [:post, 'sync/1/cancel'],
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
end
