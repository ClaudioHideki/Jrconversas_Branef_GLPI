# frozen_string_literal: true

# Plain Minitest uses refute assertions, not Rails assert_not aliases.
# rubocop:disable Rails/RefuteMethods

# Plain Minitest has refute methods, not Rails assert_not aliases.

# End-to-end requests intentionally carry several assertions; this is plain Minitest.
# rubocop:disable Metrics/AbcSize

require_relative 'intake_test_helper'

class IntakeSubmissionIntegrationTest < IntakeIntegrationTest
  def test_same_episode_reuses_row_without_changing_conversation
    original = @conversation.reload.attributes
    service = JrcServiceDesk::Intake::Submission.new
    one = service.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    two = service.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    assert_equal one.fetch(:id), two.fetch(:id)
    assert_equal 'test_only', one.fetch(:state)
    assert one.fetch(:created)
    refute two.fetch(:created)
    assert_equal 1, JrcServiceDesk::IntakeDemand.where(account: @account).count
    assert_equal original, @conversation.reload.attributes
    assert_nil one[:remote_id]
  end

  def test_incompatible_retry_is_conflict_and_never_creates_another_episode
    service = JrcServiceDesk::Intake::Submission.new
    service.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    changed = @arguments.merge('input' => @arguments.fetch('input').merge('description' => 'Changed intent'))
    assert_raises(JrcServiceDesk::IdempotencyConflict) do
      service.call(authority: @authority, conversation: @conversation, arguments: changed)
    end
    assert_equal 1, JrcServiceDesk::IntakeDemand.where(account: @account).count
  end

  def test_new_explicit_episode_can_create_another_demand_but_unknown_fields_are_rejected
    service = JrcServiceDesk::Intake::Submission.new
    service.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    another = @arguments.merge('episode_key' => SecureRandom.uuid)
    service.call(authority: @authority, conversation: @conversation, arguments: another)
    assert_equal 2, JrcServiceDesk::IntakeDemand.where(account: @account).count
    assert_raises(ArgumentError) do
      service.call(authority: @authority, conversation: @conversation, arguments: another.merge('entity_id' => 0))
    end
  end

  def test_cross_account_or_inbox_is_denied
    other_channel = Channel::Api.create!(account: @account)
    other_inbox = Inbox.create!(account: @account, channel: other_channel, name: 'Other inbox')
    configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: other_inbox, created_by_account_user: @member, revision: 1, catalogue: @catalogue,
      mode: 'on_handoff', enabled: true
    )
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation,
                                                  arguments: @arguments.merge('configuration_id' => configuration.id))
    end
    assert_empty JrcServiceDesk::IntakeDemand.where(account: @account)
  end

  def test_published_revision_and_personal_data_are_protected
    assert_raises(ActiveRecord::RecordInvalid) { @configuration.update!(catalogue: @catalogue.merge('revision' => 2)) }
    receipt = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    row = JrcServiceDesk::IntakeDemand.find(receipt.fetch(:id))
    assert_equal '12345678901', row.normalized_input.fetch('identifier')
    refute_includes row.normalized_input_before_type_cast.to_s, '12345678901'
    refute_includes receipt.to_json, 'synthetic@example.invalid'
    refute_includes receipt.to_json, 'Synthetic support request'
  end

  def test_no_glpi_request_inside_submission_and_revoked_configuration_is_denied
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Submission cannot request GLPI' }) do
      JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    end
    @configuration.update!(enabled: false)
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    end
  end

  def test_administrative_publication_keeps_old_snapshot_available_without_changing_it
    http = ActionDispatch::Integration::Session.new(Rails.application)
    headers = { 'api_access_token' => @user.access_token.token }
    path = "/api/v1/accounts/#{@account.id}/jrc_service_desk/intake/configuration"
    http.get(path, params: { inbox_id: @inbox.id }, headers: headers)
    assert_equal 200, http.response.status
    assert_equal @configuration.id.to_s, JSON.parse(http.response.body).dig('record', 'id')
    http.post(path, params: { inbox_id: @inbox.id, expected_revision: 1, catalogue: @catalogue,
                              mappings: {}, responses: [], mode: 'on_qualification', remote_writes_enabled: false }, headers: headers, as: :json)
    assert_equal 201, http.response.status
    assert @configuration.reload.enabled?
    refute @configuration.current?
    assert_equal 'on_handoff', @configuration.mode
    assert_equal 'on_qualification', JSON.parse(http.response.body).dig('record', 'mode')
    JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: @arguments)
    assert_equal @configuration.id, JrcServiceDesk::IntakeDemand.find_by!(account: @account).intake_configuration_id
  end

  def test_handoff_mode_queues_only_when_human_requested
    configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 2, catalogue: @catalogue, mode: 'on_handoff',
      enabled: true, remote_writes_enabled: true
    )
    args = @arguments.merge('configuration_id' => configuration.id, 'configuration_revision' => 2)
    service = JrcServiceDesk::Intake::Submission.new
    first = service.call(authority: @authority, conversation: @conversation, arguments: args)
    assert_equal 'qualified', first.fetch(:state)
    second = service.call(authority: @authority, conversation: @conversation, arguments: args.merge('phase' => 'handoff'))
    assert_equal 'queued', second.fetch(:state)
    assert_equal first.fetch(:id), second.fetch(:id)
  end

  def test_qualification_mode_queues_immediately
    configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 2, catalogue: @catalogue,
      mode: 'on_qualification', enabled: true, remote_writes_enabled: true
    )
    args = @arguments.merge('configuration_id' => configuration.id, 'configuration_revision' => 2)
    receipt = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: args)
    assert_equal 'queued', receipt.fetch(:state)
  end

  def test_admin_preview_validates_without_storing_personal_data_or_requesting_glpi
    http = ActionDispatch::Integration::Session.new(Rails.application)
    headers = { 'api_access_token' => @user.access_token.token }
    before = JrcServiceDesk::IntakeDemand.count
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Preview cannot request GLPI' }) do
      http.post("/api/v1/accounts/#{@account.id}/jrc_service_desk/intake/preview",
                params: { catalogue: @catalogue, input: @arguments.fetch('input') }, headers: headers, as: :json)
    end
    assert_equal 200, http.response.status
    assert_equal 4, JSON.parse(http.response.body).fetch('route_count')
    refute_includes http.response.body, '12345678901'
    refute_includes http.response.body, 'synthetic@example.invalid'
    assert_equal before, JrcServiceDesk::IntakeDemand.count
  end

  def test_foreign_configuration_cannot_be_selected_by_id
    account = Account.create!(name: 'Foreign intake account', status: 'active')
    member = AccountUser.create!(account: account, user: @user, role: 'administrator')
    channel = Channel::Api.create!(account: account)
    inbox = Inbox.create!(account: account, channel: channel, name: 'Foreign inbox')
    configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: account, inbox: inbox, created_by_account_user: member, revision: 1, catalogue: @catalogue, mode: 'on_handoff',
      enabled: true
    )
    assert_raises(ActiveRecord::RecordNotFound) do
      JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation,
                                                  arguments: @arguments.merge('configuration_id' => configuration.id))
    end
    assert_empty JrcServiceDesk::IntakeDemand.where(account: @account)
  end

  def test_agent_cannot_publish_an_intake_configuration
    http = ActionDispatch::Integration::Session.new(Rails.application)
    headers = { 'api_access_token' => @user.access_token.token }
    http.get("/api/v1/accounts/#{@account.id}/jrc_service_desk/intake/configuration",
             params: { inbox_id: @inbox.id }, headers: headers)
    assert_equal 200, http.response.status
    @member.update!(role: 'agent')
    before = JrcServiceDesk::IntakeConfiguration.count
    http.post("/api/v1/accounts/#{@account.id}/jrc_service_desk/intake/configuration",
              params: { inbox_id: @inbox.id, expected_revision: 1, catalogue: @catalogue, mappings: {}, responses: [],
                        mode: 'on_qualification', remote_writes_enabled: false }, headers: headers, as: :json)
    assert_includes [401, 403], http.response.status
    assert_equal before, JrcServiceDesk::IntakeConfiguration.count
  end
end
# rubocop:enable Metrics/AbcSize
# rubocop:enable Rails/RefuteMethods
