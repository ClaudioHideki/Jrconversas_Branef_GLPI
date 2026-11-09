# frozen_string_literal: true

# Isolated wiring regression: provider I/O and the Branef notice gate are test doubles.
# Full NoticeExecution/ActiveRecord behavior is covered by test/jrc_service_desk/intake_*.
require 'minitest/autorun'
require 'ostruct'

module Webhooks; end
module JrcServiceDesk
  module Intake
    class NoticeExecution
      class << self
        attr_accessor :mode, :calls
      end
      def initialize(_message); end
      def perform
        self.class.calls += 1
        return if self.class.mode == :blocked

        yield
      rescue StandardError
        raise unless self.class.mode == :swallow
      end
    end
  end
end
module JrcRelationship
  class SurveyMessageExecution
    def self.applies?(_message) = false
  end
end
require_relative '../../lib/webhooks/trigger'

class BranefWebhookCompatibilityTest < Minitest::Test
  class DeliveryProbe < Webhooks::Trigger
    attr_reader :deliveries
    attr_accessor :failure
    def initialize(notice: true, strict: true)
      super('https://broker.example.test/events', { event: 'message_created' }, :api_inbox_webhook, strict: strict)
      @message = OpenStruct.new(content_attributes: notice ? { 'service_desk_intake_notice_id' => 1 } : {})
      @deliveries = 0
    end
    private
    def message = @message
    def execute_delivery
      @deliveries += 1
      raise failure if failure

      @callback_completed = true
    end
  end

  def setup
    JrcServiceDesk::Intake::NoticeExecution.mode = :allow
    JrcServiceDesk::Intake::NoticeExecution.calls = 0
  end

  def test_notice_gate_is_preserved_before_a_confirmed_broker_delivery
    probe = DeliveryProbe.new
    probe.execute
    assert_equal 1, JrcServiceDesk::Intake::NoticeExecution.calls
    assert_equal 1, probe.deliveries
  end

  def test_blocked_notice_cannot_publish_or_acknowledge_a_durable_obligation
    JrcServiceDesk::Intake::NoticeExecution.mode = :blocked
    probe = DeliveryProbe.new
    assert_raises(Webhooks::Trigger::DeliveryNotConfirmed) { probe.execute }
    assert_equal 0, probe.deliveries
  end

  def test_swallowed_provider_failure_is_not_a_successful_acknowledgement
    JrcServiceDesk::Intake::NoticeExecution.mode = :swallow
    probe = DeliveryProbe.new
    probe.failure = IOError.new('synthetic receiver outage')
    assert_raises(Webhooks::Trigger::DeliveryNotConfirmed) { probe.execute }
    assert_equal 1, probe.deliveries
  end

  def test_non_strict_blocked_notice_keeps_its_existing_no_dispatch_behavior
    JrcServiceDesk::Intake::NoticeExecution.mode = :blocked
    probe = DeliveryProbe.new(strict: false)
    probe.execute
    assert_equal 0, probe.deliveries
  end

  def test_ordinary_messages_do_not_enter_the_branef_notice_gate
    probe = DeliveryProbe.new(notice: false)
    probe.execute
    assert_equal 0, JrcServiceDesk::Intake::NoticeExecution.calls
    assert_equal 1, probe.deliveries
  end
end