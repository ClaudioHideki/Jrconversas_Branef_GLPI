# frozen_string_literal: true

# Plain Minitest scenarios intentionally exercise complete, flat source/receipt transitions.
# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Rails/RefuteMethods
require_relative 'intake_delivery_test_helper'

class IntakeLifecycleIntegrationTest < IntakeDeliveryTest
  def setup
    super
    @conversation.contact.update!(phone_number: '+12025550123')
    @inbox.channel.update!(webhook_url: "https://broker.example.test/v1/integrations/chatwoot/#{@binding.integration_id}/events",
                           secret: SecureRandom.hex(32))
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      raise 'Synthetic delivery setup failed' unless result.fetch(:state) == 'confirmed'
    end
    @remote.rows.fetch('Ticket/501')['status'] = 4
  end

  def intake_responses
    [{ 'code' => 'pending_information', 'template' => 'Synthetic request for information. Reply within 48 hours.',
       'parameters' => [], 'requires_confirmation' => true },
     { 'code' => 'satisfaction', 'template' => 'Synthetic satisfaction invitation after human completion.',
       'parameters' => [], 'requires_confirmation' => true }]
  end

  def intake_notifications
    { 'enabled' => true, 'channel' => 'whatsapp', 'owner' => 'jrc',
      'pending_information_template' => 'pending_information', 'survey_template' => 'satisfaction' }
  end

  def test_no_delivery_receipt_means_no_clock
    notice = prepare_notice
    JrcServiceDesk::Intake::PendingInformation.new.start(demand_id: @demand.id, notice_id: notice.id)
    assert_nil @demand.reload.waiting_deadline
    assert_equal 'awaiting_delivery', @demand.lifecycle_state
  end

  def test_only_a_native_matching_delivery_receipt_starts_48_elapsed_hours_once
    notice = delivered_notice
    deadline = @demand.reload.waiting_deadline
    assert_equal notice.delivered_at + 48.hours, deadline
    generation = @demand.waiting_generation
    JrcServiceDesk::Intake::PendingInformation.new.start(demand_id: @demand.id, notice_id: notice.id)
    assert_equal deadline, @demand.reload.waiting_deadline
    assert_equal generation, @demand.waiting_generation
  end

  def test_changing_message_payload_prevents_a_fake_delivery_clock
    notice = prepare_notice
    notice.message.update!(content: 'Substituted payload', status: :delivered, source_id: 'synthetic-provider')
    JrcServiceDesk::Intake::Notification.new.observe_message(message_id: notice.message_id)
    assert_nil @demand.reload.waiting_deadline
    assert_nil notice.reload.delivered_at
  end

  def test_response_before_receipt_cancels_even_if_the_listener_has_not_run
    notice = prepare_notice
    incoming
    acknowledge(notice)
    assert_nil @demand.reload.waiting_deadline
    assert_equal 'cancelled', @demand.lifecycle_state
  end

  def test_newest_persisted_inbound_beats_a_stale_expiry_worker
    notice = delivered_notice
    incoming
    expire(notice)
    assert_equal 'cancelled', @demand.reload.lifecycle_state
    assert_equal 4, @remote.rows.fetch('Ticket/501').fetch('status')
  end

  def test_human_takeover_invalidates_pending_automatic_closure
    notice = delivered_notice
    @conversation.update!(assignee: @user, status: :open)
    expire(notice)
    assert_equal 'cancelled', @demand.reload.lifecycle_state
    assert_equal 4, @remote.rows.fetch('Ticket/501').fetch('status')
  end

  def test_reply_arriving_during_source_validation_cancels_before_close_write
    notice = delivered_notice
    @remote.on_profile = -> { incoming }
    expire(notice)
    assert_equal 'cancelled', @demand.reload.lifecycle_state
    refute(@remote.writes.any? { |_verb, _type, _id, input| input['status'] == 6 })
  end

  def test_missing_remote_rights_never_closes_only_the_local_projection
    notice = delivered_notice
    @remote.denied = true
    expire(notice)
    assert_equal 'needs_attention', @demand.reload.lifecycle_state
    assert_equal 4, @remote.rows.fetch('Ticket/501').fetch('status')
    refute @conversation.reload.resolved?
  end

  def test_no_response_closure_is_confirmed_at_source_and_excluded_from_survey
    notice = delivered_notice
    expire(notice)
    assert_equal 'closed_no_response', @demand.reload.lifecycle_state
    assert_equal 'no_response', @demand.completion_cause
    assert_equal 6, @remote.rows.fetch('Ticket/501').fetch('status')
    assert @conversation.reload.resolved?, 'Local resolution requires confirmed remote closure'
    refute JrcServiceDesk::Intake::Notification.eligible?(demand: @demand, channel: 'whatsapp')
    assert_empty JrcServiceDesk::IntakeNotification.where(intake_demand: @demand, kind: 'survey')
  end

  def test_old_generation_cannot_close_a_new_information_request
    old = delivered_notice
    current = delivered_notice
    expire(old)
    assert_equal current.generation, @demand.reload.waiting_generation
    assert_equal 'awaiting_information', @demand.lifecycle_state
    assert_equal 4, @remote.rows.fetch('Ticket/501').fetch('status')
  end

  def test_two_workers_confirm_only_one_remote_close
    notice = delivered_notice
    deadline = @demand.reload.waiting_deadline
    pool = ActiveRecord::Base.connection_pool
    warmed = Array.new(2) { pool.checkout }
    warmed.each { |connection| connection.select_value('SELECT 1') }
    warmed.each { |connection| pool.checkin(connection) }
    connection_ids = Queue.new
    Time.stub(:current, deadline + 1.second) do
      JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
        workers = 2.times.map do
          Thread.new do
            pool.with_connection do |connection|
              connection_ids << connection.object_id
              JrcServiceDesk::Intake::PendingInformation.new.expire(demand_id: @demand.id, generation: notice.generation)
            end
          end
        end
        workers.each(&:value)
        assert_equal 2, Array.new(2) { connection_ids.pop }.uniq.size
      end
    end
    assert_equal 'closed_no_response', @demand.reload.lifecycle_state
    closes = @remote.writes.count { |_verb, _type, _id, input| input['status'] == 6 }
    assert_equal 1, closes
  end

  def test_revoked_configuration_cancels_before_requesting_the_source
    notice = delivered_notice
    @delivery_configuration.update!(enabled: false)
    Time.stub(:current, @demand.reload.waiting_deadline + 1.second) do
      JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Revoked rule cannot request GLPI' }) do
        JrcServiceDesk::Intake::PendingInformation.new.expire(demand_id: @demand.id, generation: notice.generation)
      end
    end
    assert_equal 'cancelled', @demand.reload.lifecycle_state
  end

  def test_duplicate_human_completion_has_only_one_survey_intent
    @remote.rows.fetch('Ticket/501')['status'] = 6
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      2.times do
        JrcServiceDesk::Intake::Notification.new.complete(demand_id: @demand.id, operator_context: @identity, source_version: 'v2')
      end
    end
    assert_equal 'completed_human', @demand.reload.lifecycle_state
    assert_equal 1, JrcServiceDesk::IntakeNotification.where(intake_demand: @demand, kind: 'survey').count
  end

  def test_unavailable_channel_keeps_notice_blocked_without_claiming_delivery
    @inbox.channel.update!(webhook_url: nil)
    notice = JrcServiceDesk::Intake::Notification.new.call(demand_id: @demand.id, kind: 'pending_information',
                                                           operator_context: @identity, request_key: SecureRandom.uuid, human_confirmation: true)
    assert_equal 'blocked', notice.state
    assert_nil notice.message_id
    assert_nil notice.delivered_at
    assert_nil @demand.reload.waiting_deadline
  end

  def test_notice_cannot_follow_a_changed_broker_binding
    notice = JrcServiceDesk::Intake::Notification.new.call(demand_id: @demand.id, kind: 'pending_information',
                                                           operator_context: @identity, request_key: SecureRandom.uuid, human_confirmation: true)
    @binding.update!(instance_id: SecureRandom.uuid)
    JrcServiceDesk::IntakeNotificationJob.perform_now(notice.id)
    assert_equal 'blocked', notice.reload.state
    assert_nil notice.message_id
  end

  def test_notice_cannot_follow_a_changed_routing_identity
    notice = prepare_notice
    @conversation.contact_inbox.update!(source_id: SecureRandom.uuid)
    sent = false
    JrcServiceDesk::Intake::NoticeExecution.new(notice.message).perform { sent = true }
    refute sent
    assert_equal 'blocked', notice.reload.state
  end

  def test_unconfirmed_operator_cannot_prepare_a_notice
    @user.update!(confirmed_at: nil)
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Intake::Notification.new.call(demand_id: @demand.id, kind: 'pending_information',
                                                    operator_context: @identity, request_key: SecureRandom.uuid, human_confirmation: true)
    end
  end

  def test_additional_attributes_cannot_be_substituted_after_approval
    notice = prepare_notice
    notice.message.update!(additional_attributes: { 'synthetic_unapproved' => true })
    sent = false
    JrcServiceDesk::Intake::NoticeExecution.new(notice.message).perform { sent = true }
    refute sent
    assert_equal 'blocked', notice.reload.state
  end

  def test_unknown_transport_result_is_not_sent_twice_and_starts_no_clock
    notice = prepare_notice
    count = 0
    2.times do
      JrcServiceDesk::Intake::NoticeExecution.new(notice.message).perform { count += 1 }
    end
    assert_equal 1, count
    assert_equal 'unknown', notice.reload.state
    assert_nil @demand.reload.waiting_deadline
  end

  def test_new_response_before_notice_dispatch_prevents_the_old_notice
    notice = prepare_notice
    incoming
    sent = false
    JrcServiceDesk::Intake::NoticeExecution.new(notice.message).perform { sent = true }
    refute sent
    assert_equal 'blocked', notice.reload.state
  end

  def test_owned_intake_closure_cannot_trigger_a_second_native_survey
    @demand.update!(lifecycle_state: 'closed_no_response', completion_cause: 'no_response')
    @conversation.update!(status: :resolved)
    event = Struct.new(:data).new({ conversation: @conversation })
    JrcRelationship::SurveyClosureJob.stub(:perform_later, ->(*) { flunk 'No relationship survey for owned intake closure' }) do
      CsatSurveyService.stub(:new, ->(*) { flunk 'No duplicate native CSAT for owned intake closure' }) do
        CsatSurveyListener.instance.conversation_status_changed(event)
      end
    end
  end

  private

  def prepare_notice
    notice = JrcServiceDesk::Intake::Notification.new.call(demand_id: @demand.id, kind: 'pending_information',
                                                           operator_context: @identity, request_key: SecureRandom.uuid, human_confirmation: true)
    JrcServiceDesk::IntakeNotificationJob.perform_now(notice.id)
    notice.reload
  end

  def delivered_notice
    notice = prepare_notice
    acknowledge(notice)
    notice.reload
  end

  def acknowledge(notice)
    notice.message.update!(status: :delivered, source_id: 'synthetic-provider')
    JrcServiceDesk::Intake::Notification.new.observe_message(message_id: notice.message_id)
  end

  def incoming
    Message.create!(account: @account, inbox: @inbox, conversation: @conversation, sender: @conversation.contact,
                    message_type: :incoming, content: 'Synthetic customer reply')
  end

  def expire(notice)
    deadline = @demand.reload.waiting_deadline
    Time.stub(:current, deadline + 1.second) do
      JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
        JrcServiceDesk::Intake::PendingInformation.new.expire(demand_id: @demand.id, generation: notice.generation)
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Rails/RefuteMethods
