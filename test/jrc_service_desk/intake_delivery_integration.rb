# frozen_string_literal: true

# Plain Minitest uses refute assertions, not Rails assert_not aliases.
# rubocop:disable Rails/RefuteMethods

# Plain Minitest has refute methods, not Rails assert_not aliases.

# Flat synthetic integration scenarios use plain Minitest assertions.
# rubocop:disable Metrics/AbcSize

require_relative 'intake_delivery_test_helper'

# A stateful external-source fixture behind the real durable GLPI executor.
class IntakeDeliveryIntegrationTest < IntakeDeliveryTest
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

# rubocop:enable Metrics/AbcSize
# rubocop:enable Rails/RefuteMethods
