# frozen_string_literal: true

# Plain Minitest has refute methods, not Rails assert_not aliases.
# rubocop:disable Rails/RefuteMethods

# Flat synthetic integration scenarios use plain Minitest assertions.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength

require_relative 'intake_test_helper'
require_relative 'intake_source_fixture'

# A stateful external-source fixture behind the real durable GLPI executor.
class IntakeDeliveryIntegrationTest < IntakeIntegrationTest
  def setup
    super
    @connection.update!(primary_source: true)
    JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
    @remote = IntakeGlpiSource.new
    @remote.rows.merge!(
      'User/77' => { 'id' => 77, 'name' => 'Synthetic requester', 'is_active' => 1 },
      'Group/20' => { 'id' => 20, 'name' => 'Synthetic N2/N3', 'entities_id' => 0, 'is_recursive' => 1, 'is_assign' => 1 },
      'ITILCategory/10' => { 'id' => 10, 'name' => 'Synthetic access', 'entities_id' => 0, 'is_recursive' => 1,
                             'is_request' => 1, 'is_incident' => 1, 'tickettemplates_id_demand' => 0, 'tickettemplates_id_incident' => 0 },
      'SLA/30' => { 'id' => 30, 'name' => 'Synthetic five days', 'entities_id' => 0, 'slms_id' => 40,
                    'type' => 0, 'number_time' => 5, 'definition_time' => 'day', 'calendars_id' => 0 },
      'SLM/40' => { 'id' => 40, 'name' => 'Synthetic agreement', 'entities_id' => 0, 'is_recursive' => 1,
                    'calendars_id' => 0, 'use_ticket_calendar' => 0 }
    )
    @delivery_configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 2, catalogue: @catalogue,
      mode: 'on_qualification', enabled: true, remote_writes_enabled: true,
      mappings: { 'routes' => [{ 'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
                                 'profile' => 'requester', 'severity' => nil, 'entity_id' => 0, 'category_id' => 10, 'group_id' => 20,
                                 'requester_policy' => 'mapped_contact', 'sla' => { 'id' => 30, 'purpose' => 'resolve', 'calendar_id' => 0 } }],
                  'requesters' => [{ 'contact_id' => @conversation.contact_id, 'entity_id' => 0, 'user_id' => 77 }] }
    )
    args = @arguments.merge('configuration_id' => @delivery_configuration.id, 'configuration_revision' => 2)
    receipt = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: args)
    @demand = JrcServiceDesk::IntakeDemand.find(receipt.fetch(:id))
    @captured_context = @demand.source_context.deep_dup
    @demand.update!(source_context: @demand.source_context.merge(
      'service_token_id' => @access_token.id, 'service_token_fingerprint' => Digest::SHA256.hexdigest(@access_token.token),
      'organization_id' => @organization, 'integration_id' => @integration,
      'routing_source_hash' => JrcFlowEffects::ControlRevision.snapshot(@conversation).fetch('routing_source_hash'),
      'assignee_id' => nil, 'assignee_agent_bot_id' => nil, 'team_id' => nil, 'conversation_status' => 'pending'
    ))
  end

  def test_submission_captures_credential_generation_without_persisting_the_token
    assert_equal @access_token.id, @captured_context.fetch('service_token_id')
    assert_equal Digest::SHA256.hexdigest(@access_token.token), @captured_context.fetch('service_token_fingerprint')
    assert_equal @binding.integration_id, @captured_context.fetch('integration_id')
    assert_equal @connection.id, @captured_context.fetch('connection_id')
    refute_includes @captured_context.to_json, @access_token.token
  end

  def test_disabled_real_writes_never_constructs_a_client
    receipt = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation,
                                                          arguments: @arguments.merge('episode_key' => SecureRandom.uuid))
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Disabled intake cannot request GLPI' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: receipt.fetch(:id))
      assert_equal 'test_only', result.fetch(:state)
    end
  end

  def test_confirmed_delivery_has_one_ticket_and_separate_group_and_sla_receipts
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'confirmed', result.fetch(:state)
      assert_equal '501', result.fetch(:remote_id)
      assert_equal 'succeeded', result.dig(:stages, 'assignment', 'state')
      assert_equal 'succeeded', result.dig(:stages, 'sla', 'state')
      assert_equal 20, @remote.rows.fetch('Ticket/501').fetch('_groups_id_assign')
      assert_equal 30, @remote.rows.fetch('Ticket/501').fetch('slas_id_ttr')
      assert_equal 77, @remote.rows.fetch('Ticket/501').fetch('_users_id_requester')
      assert_equal 1, JrcServiceDesk::GlpiReferenceLink.where(account: @account, conversation: @conversation).count
      assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
      JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal(1, @remote.writes.count { |verb, type, _id, _input| verb == :post && type == 'Ticket' })
    end
  end

  def test_group_failure_keeps_the_created_protocol_and_never_recreates_ticket
    @remote.fail_assignment = true
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'partial', result.fetch(:state)
      assert_equal '501', result.fetch(:remote_id)
      refute_equal 'succeeded', result.dig(:stages, 'assignment', 'state')
      JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal(1, @remote.writes.count { |verb, type, _id, _input| verb == :post && type == 'Ticket' })
    end
  end

  def test_timeout_after_remote_create_is_indeterminate_and_is_not_replayed
    @remote.fail_after_create = true
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'indeterminate', result.fetch(:state)
      assert_nil result[:remote_id]
      JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal(1, @remote.writes.count { |verb, type, _id, _input| verb == :post && type == 'Ticket' })
    end
  end

  def test_revoked_service_token_blocks_before_constructing_a_client
    @access_token.destroy!
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Revoked credential cannot request GLPI' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
    assert_empty @remote.writes
  end

  def test_revoked_binding_blocks_before_constructing_a_client
    @binding.destroy!
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Revoked binding cannot request GLPI' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
    assert_empty @remote.writes
  end

  def test_wrong_sla_calendar_does_not_create_a_ticket
    @remote.rows['SLM/40']['calendars_id'] = 22
    @remote.rows['SLA/30']['calendars_id'] = 22
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
    assert_empty @remote.writes
  end

  def test_human_takeover_blocks_future_bot_delivery
    @conversation.update!(assignee: @user, status: :open)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Human takeover must stop the bot before GLPI' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
  end

  def test_revoked_operational_unit_grant_blocks_before_constructing_a_client
    JrcServiceDesk::UnitMembership.find_by!(account: @account, unit: @unit, account_user: @member).update!(active: false)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Revoked operational grant cannot request GLPI' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
  end

  def test_rotated_service_token_does_not_authorize_an_old_queued_intent
    @access_token.update!(token: SecureRandom.hex(32))
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'An old credential generation cannot request GLPI' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
  end

  def test_changed_glpi_connection_blocks_before_constructing_a_client
    @connection.update!(timezone: 'America/Sao_Paulo')
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Changed GLPI destination cannot receive an old queued intent' }) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
  end

  def test_sla_duration_is_not_guessed_from_a_calendar
    @remote.rows['SLA/30']['number_time'] = 4
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result.fetch(:state)
    end
    assert_empty @remote.writes
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/MethodLength

# rubocop:enable Rails/RefuteMethods
