# frozen_string_literal: true

# Independent review regressions intentionally keep native end-to-end state visible.
# rubocop:disable Metrics/AbcSize, Rails/RefuteMethods
require_relative 'intake_delivery_test_helper'
require_relative 'intake_readiness_probe'

class IntakeReviewIntegrationTest < IntakeDeliveryTest
  def setup
    super
    @conversation.contact.update!(phone_number: '+12025550123')
    @inbox.channel.update!(webhook_url: "https://broker.example.test/v1/integrations/chatwoot/#{@binding.integration_id}/events",
                           secret: SecureRandom.hex(32))
  end

  def intake_responses
    [{ 'code' => 'pending', 'template' => 'Synthetic information request', 'parameters' => [], 'requires_confirmation' => true }]
  end

  def intake_notifications
    { 'enabled' => true, 'channel' => 'whatsapp', 'owner' => 'jrc', 'pending_information_template' => 'pending' }
  end

  def test_unit_revocation_denies_status_replay_and_receipt_without_new_commands
    deliver
    service = JrcServiceDesk::Intake::DomainCommand.new
    arguments = { 'command' => 'service_desk_status', 'episode_key' => @demand.episode_key }
    result = service.call(authority: @authority, conversation: @conversation, arguments: arguments, operation_id: SecureRandom.uuid)
    counts = [JrcServiceDesk::IntakeDemand.count, JrcServiceDesk::GlpiCommand.count]
    JrcServiceDesk::UnitMembership.where(account: @account).delete_all
    assert_raises(Pundit::NotAuthorizedError) do
      service.call(authority: @authority, conversation: @conversation, arguments: arguments, operation_id: SecureRandom.uuid)
    end
    assert_raises(Pundit::NotAuthorizedError) do
      replay = @arguments.merge('configuration_id' => @delivery_configuration.id, 'configuration_revision' => 2)
      JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation,
                                                  arguments: replay)
    end
    assert_raises(Pundit::NotAuthorizedError) do
      service.authorize_receipt!(account: @account, user: @user, conversation: @conversation, result: result)
    end
    assert_equal counts, [JrcServiceDesk::IntakeDemand.count, JrcServiceDesk::GlpiCommand.count]
  end

  def test_human_takeover_before_delivery_receipt_cancels_the_clock
    assert_control_before_receipt { @conversation.update!(status: :open, assignee: @user) }
  end

  def test_team_change_before_delivery_receipt_cancels_the_clock
    assert_control_before_receipt do
      team = Team.create!(account: @account, name: 'Synthetic team')
      @conversation.update!(team: team)
    end
  end

  def test_bot_change_before_delivery_receipt_cancels_the_clock
    assert_control_before_receipt do
      bot = AgentBot.create!(account: @account, name: 'Synthetic bot', outgoing_url: 'https://example.invalid/events')
      @conversation.update!(assignee_agent_bot: bot)
    end
  end

  def test_readiness_and_enabled_publication_use_only_get_including_session_setup
    probe = IntakeReadinessProbe.new(@connection, @remote)
    JrcServiceDesk::Glpi::Client.stub(:new, probe) do
      result = JrcServiceDesk::Intake::Readiness.new.call(user_context: @identity, attributes: draft)
      assert result.fetch(:ready), result.inspect
      JrcServiceDesk::Intake::Publish.new.call(user_context: @identity,
                                               attributes: draft.merge('expected_revision' => 2,
                                                                       'remote_writes_enabled' => true))
    end
    assert(probe.requests.any? { |verb, path| verb == :get && path == 'initSession/' })
    assert probe.requests.all? { |verb, _path| verb == :get }, probe.requests.inspect
    assert_empty @remote.writes
  end

  def test_readable_metadata_without_source_write_rights_is_not_ready
    @remote.denied = true
    probe = IntakeReadinessProbe.new(@connection, @remote)
    JrcServiceDesk::Glpi::Client.stub(:new, probe) do
      result = JrcServiceDesk::Intake::Readiness.new.call(user_context: @identity, attributes: draft)
      refute result.fetch(:ready)
      assert_includes result.fetch(:blockers), 'operation_not_permitted'
      assert_raises(ArgumentError) do
        JrcServiceDesk::Intake::Publish.new.call(user_context: @identity,
                                                 attributes: draft.merge('expected_revision' => 2,
                                                                         'remote_writes_enabled' => true))
      end
    end
    assert_equal 2, JrcServiceDesk::IntakeConfiguration.where(account: @account).count
    assert_empty @remote.writes
  end

  private

  def deliver
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) { JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id) }
    assert_equal 'confirmed', @demand.reload.state
  end

  def assert_control_before_receipt
    deliver
    @remote.rows.fetch('Ticket/501')['status'] = 4
    notice = JrcServiceDesk::Intake::Notification.new.call(demand_id: @demand.id, kind: 'pending_information',
                                                           operator_context: @identity, request_key: SecureRandom.uuid, human_confirmation: true)
    JrcServiceDesk::IntakeNotificationJob.perform_now(notice.id)
    notice.reload
    JrcServiceDesk::Intake::NoticeExecution.new(notice.message).perform { notice.message.update!(source_id: 'synthetic-provider') }
    yield
    JrcServiceDesk::Intake::PendingInformation.new.cancel_conversation(conversation_id: @conversation.id)
    notice.message.update!(status: :delivered)
    JrcServiceDesk::Intake::Notification.new.observe_message(message_id: notice.message_id)
    assert_equal 'cancelled', @demand.reload.lifecycle_state
    assert_nil @demand.waiting_deadline
    assert_nil @demand.waiting_generation
    assert_equal 4, @remote.rows.fetch('Ticket/501').fetch('status')
  end

  def draft
    catalogue = @catalogue.deep_dup
    system = catalogue.fetch('systems').first
    system['locations'].select! { |row| row['code'] == 'south' }
    system['profiles'].select! { |row| row['code'] == 'requester' }
    system['reasons'].select! { |row| row['code'] == 'request' }
    { 'inbox_id' => @inbox.id, 'catalogue' => catalogue, 'responses' => [],
      'mappings' => @delivery_configuration.mappings, 'mode' => 'on_handoff', 'remote_writes_enabled' => false }
  end
end
# rubocop:enable Metrics/AbcSize, Rails/RefuteMethods
