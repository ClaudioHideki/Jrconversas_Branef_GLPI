# frozen_string_literal: true

require_relative 'intake_delivery_test_helper'

# Integration scenarios deliberately keep transaction and delivery assertions together.
# rubocop:disable Metrics/AbcSize, Rails/RefuteMethods
class IntakeHandoffIntegrationTest < IntakeDeliveryTest
  def setup
    super
    @team = Team.create!(account: @account, name: 'Synthetic support', allow_auto_assign: false)
    @handoff = @arguments.merge('command' => 'service_desk_handoff', 'phase' => 'handoff',
                                'configuration_id' => @delivery_configuration.id, 'configuration_revision' => 2, 'episode_key' => SecureRandom.uuid,
                                'target' => { 'team_id' => @team.id, 'agent_id' => nil })
    @effect = { 'organization_id' => @organization, 'integration_id' => @integration,
                'operation_id' => SecureRandom.uuid, 'dispatch_proof' => SecureRandom.uuid, 'inbox_id' => @inbox.id.to_s,
                'remote_contact_id' => @conversation.contact_id.to_s,
                'expected_control_revision' => @conversation.reload.jrc_effect_control_revision.to_s,
                'operation' => 'domain', 'value_json' => JSON.generate(@handoff) }
    @apply = JrcFlowEffects::Apply.new(account: @account, user: @user, access_token: @access_token)
  end

  def test_handoff_commits_before_any_glpi_request_and_delivery_survives_human_control
    receipt = JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Handoff must never wait for GLPI' }) do
      @apply.call(@conversation.display_id, @effect)
    end
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
    assert_nil @conversation.assignee_agent_bot_id
    demand = JrcServiceDesk::IntakeDemand.find(receipt.domain_result.dig('intake', 'id'))
    assert_equal 'queued', demand.state
    assert(ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job] == JrcServiceDesk::IntakeDeliveryJob && job[:args] == [demand.id] })
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: demand.id)
      assert_equal 'confirmed', result[:state], result.inspect
    end
    assert_equal @team.id, @conversation.reload.team_id
    assert @conversation.open?
  end

  def test_glpi_timeout_keeps_the_human_handoff_and_never_reposts
    receipt = @apply.call(@conversation.display_id, @effect)
    demand = JrcServiceDesk::IntakeDemand.find(receipt.domain_result.dig('intake', 'id'))
    @remote.fail_after_create = true
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      first = JrcServiceDesk::Intake::Delivery.new.call(demand_id: demand.id)
      assert_equal 'indeterminate', first[:state], first.inspect
      JrcServiceDesk::Intake::Delivery.new.call(demand_id: demand.id)
    end
    assert_equal 1, @remote.writes.size
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
  end

  def test_invalid_collection_still_reaches_humans_with_a_private_warning
    @effect['value_json'] = JSON.generate(@handoff.deep_merge('input' => { 'email' => 'invalid' }))
    receipt = @apply.call(@conversation.display_id, @effect)
    assert_nil receipt.domain_result['intake']
    assert_equal 'intake_collection_invalid', receipt.domain_result['error_code']
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
    assert @conversation.messages.exists?(private: true)
    assert_empty @remote.writes
  end

  def test_replay_after_lost_response_does_not_register_or_handoff_again
    first = @apply.call(@conversation.display_id, @effect)
    demands = JrcServiceDesk::IntakeDemand.where(account: @account).count
    notes = @conversation.messages.where(private: true).count
    second = @apply.call(@conversation.display_id, @effect)
    assert_equal first.id, second.id
    assert_equal demands, JrcServiceDesk::IntakeDemand.where(account: @account).count
    assert_equal notes, @conversation.messages.where(private: true).count
  end

  def test_foreign_team_never_changes_conversation_or_registers_intake
    foreign = Team.create!(account: Account.create!(name: 'Other account'), name: 'Foreign')
    @effect['value_json'] = JSON.generate(@handoff.deep_merge('target' => { 'team_id' => foreign.id }))
    assert_raises(ActiveRecord::RecordNotFound) { @apply.call(@conversation.display_id, @effect) }
    assert @conversation.reload.pending?
    assert_nil @conversation.team_id
  end

  def test_handoff_admission_does_not_override_credential_revocation
    receipt = @apply.call(@conversation.display_id, @effect)
    demand = JrcServiceDesk::IntakeDemand.find(receipt.domain_result.dig('intake', 'id'))
    @access_token.destroy!
    result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: demand.id)
    assert_equal 'rejected', result[:state]
    assert_empty @remote.writes
    assert_equal @team.id, @conversation.reload.team_id
  end

  def test_glpi_permission_denial_does_not_undo_human_assignment
    receipt = @apply.call(@conversation.display_id, @effect)
    @remote.denied = true
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: receipt.domain_result.dig('intake', 'id'))
      assert_equal 'rejected', result[:state], result.inspect
    end
    assert_empty @remote.writes
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
  end

  def test_another_demand_cannot_reuse_the_handoff_admission
    @apply.call(@conversation.display_id, @effect)
    @demand.update!(source_context: @demand.source_context.merge('handoff_operation_id' => @effect.fetch('operation_id')))
    result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
    assert_equal 'rejected', result[:state]
    assert_empty @remote.writes
    assert_equal @team.id, @conversation.reload.team_id
  end

  def test_disabled_intake_configuration_still_transfers_without_enqueuing_a_glpi_request
    @configuration.update!(enabled: false)
    @delivery_configuration.update!(enabled: false)
    http = ActionDispatch::Integration::Session.new(Rails.application)
    http.get("/api/v1/accounts/#{@account.id}/jrc_domain_commands/capabilities",
             params: { inbox_id: @inbox.id, organization_id: @organization, integration_id: @integration, intake_protocol: '2' },
             headers: { 'api_access_token' => @access_token.token })
    assert_equal 200, http.response.status
    assert_includes JSON.parse(http.response.body).fetch('commands'), 'service_desk_handoff'
    receipt = @apply.call(@conversation.display_id, @effect)
    assert_nil receipt.domain_result['intake']
    assert_equal 'intake_not_ready', receipt.domain_result['error_code']
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
    assert_empty @remote.writes
  end

  def test_missing_current_intake_configuration_still_advertises_handoff
    @configuration.update!(current: false)
    http = ActionDispatch::Integration::Session.new(Rails.application)
    http.get("/api/v1/accounts/#{@account.id}/jrc_domain_commands/capabilities",
             params: { inbox_id: @inbox.id, organization_id: @organization, integration_id: @integration, intake_protocol: '2' },
             headers: { 'api_access_token' => @access_token.token })
    assert_equal 200, http.response.status
    commands = JSON.parse(http.response.body).fetch('commands')
    assert_includes commands, 'service_desk_handoff'
    refute_includes commands, 'service_desk_intake'
  end

  def test_invalid_rendered_capture_routes_to_humans_for_manual_review
    @effect['value_json'] = JSON.generate(@handoff.merge('input' => {}, 'capture_error' => 'intake_capture_invalid'))
    receipt = @apply.call(@conversation.display_id, @effect)
    assert_nil receipt.domain_result['intake']
    assert_equal 'intake_capture_invalid', receipt.domain_result['error_code']
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
    assert_empty @remote.writes
  end

  def test_oversized_capture_routes_to_humans_without_inventing_or_truncating_a_ticket
    @effect['value_json'] = JSON.generate(@handoff.merge('input' => {}, 'capture_error' => 'intake_capture_too_large'))
    receipt = @apply.call(@conversation.display_id, @effect)
    assert_nil receipt.domain_result['intake']
    assert_equal 'intake_capture_too_large', receipt.domain_result['error_code']
    assert @conversation.reload.open?
    assert_equal @team.id, @conversation.team_id
    assert_empty @remote.writes
  end
end
# rubocop:enable Metrics/AbcSize, Rails/RefuteMethods
