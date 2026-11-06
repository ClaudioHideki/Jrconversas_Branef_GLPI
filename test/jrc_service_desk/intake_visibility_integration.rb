# frozen_string_literal: true

# End-to-end authorization and readiness scenarios use synthetic data only.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Rails/RefuteMethods
require_relative 'intake_delivery_test_helper'

class IntakeVisibilityIntegrationTest < IntakeDeliveryTest
  def setup
    super
    @http = ActionDispatch::Integration::Session.new(Rails.application)
    @headers = { 'api_access_token' => @access_token.token }
    @path = "/api/v1/accounts/#{@account.id}/jrc_service_desk/intake"
  end

  def test_account_inboxes_are_authenticated_and_scoped
    @http.get("#{@path}/inboxes", headers: @headers)
    assert_equal 200, @http.response.status
    result = JSON.parse(@http.response.body)
    assert_equal @account.id.to_s, result.fetch('account_id')
    assert_equal @user.id.to_s, result.fetch('user_id')
    assert_equal [@inbox.id.to_s], result.fetch('inboxes').map { |row| row.fetch('id') }
  end

  def test_incomplete_mapping_preview_never_claims_ready_or_requests_glpi
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Incomplete preview cannot request GLPI' }) do
      @http.post("#{@path}/readiness", params: draft.merge(mappings: {}), headers: @headers, as: :json)
    end
    assert_equal 200, @http.response.status
    body = JSON.parse(@http.response.body)
    refute body.fetch('ready')
    assert_includes body.fetch('blockers'), 'intake_route_unmapped'
    assert_equal 28, body.fetch('selection_count')
    assert_equal 0, JrcServiceDesk::IntakeNotification.where(account: @account).count
  end

  def test_mapping_without_explicit_sla_calendar_cannot_enable_remote_writes
    values = draft
    values[:mappings]['routes'][0]['sla'].delete('calendar_id')
    @http.post("#{@path}/readiness", params: values, headers: @headers, as: :json)
    assert_equal 200, @http.response.status
    refute JSON.parse(@http.response.body).fetch('ready')
    @http.post("#{@path}/configuration", params: values.merge(expected_revision: 2, remote_writes_enabled: true),
      headers: @headers, as: :json)
    assert_equal 409, @http.response.status
    assert_equal 2, JrcServiceDesk::IntakeConfiguration.where(account: @account).count
  end

  def test_demand_is_visible_without_taking_over_the_conversation
    before = @conversation.reload.attributes
    @http.get("#{@path}/conversations/#{@conversation.display_id}", headers: @headers)
    assert_equal 200, @http.response.status
    rows = JSON.parse(@http.response.body).fetch('demands')
    assert_equal [@demand.id.to_s], rows.map { |row| row.fetch('id') }
    assert_equal 'example', rows.first.fetch('selection').fetch('system')
    refute_includes @http.response.body, '12345678901'
    refute_includes @http.response.body, 'synthetic@example.invalid'
    assert_equal before, @conversation.reload.attributes
  end

  def test_foreign_conversation_is_not_visible
    foreign = Account.create!(name: 'Other synthetic account')
    @http.get("/api/v1/accounts/#{foreign.id}/jrc_service_desk/intake/conversations/#{@conversation.display_id}", headers: @headers)
    assert_includes [401, 403, 404], @http.response.status
  end

  def test_explicit_unit_grant_revocation_hides_intake_metadata
    JrcServiceDesk::UnitMembership.where(account: @account).delete_all
    @http.get("#{@path}/conversations/#{@conversation.display_id}", headers: @headers)
    assert_equal 200, @http.response.status
    assert_empty JSON.parse(@http.response.body).fetch('demands')
  end

  private

  def draft
    { inbox_id: @inbox.id, catalogue: @catalogue, responses: [], mode: 'on_handoff',
      mappings: @delivery_configuration.mappings.deep_dup, remote_writes_enabled: false }
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Rails/RefuteMethods
