# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'logger'

module Pundit
  class NotAuthorizedError < StandardError; end
end

module ActiveRecord
  class RecordNotFound < StandardError; end
end

module Rails
  def self.logger = Logger.new($stderr)
end

# Synthetic job dependencies. The real operation service is loaded below.
module JrcServiceDesk
  module Intake
    class Readiness
      KEYS = %w[inbox_id].freeze
    end

    class Publish
      KEYS = %w[inbox_id expected_revision remote_writes_enabled].freeze
    end
  end

  class IntakeConfigurationJob
    def self.perform_later(*) = raise('Stub job enqueue')
  end
end

class AccountUser
  def self.find_by!(**) = raise('Stub account membership lookup')
end

class Redis
  class Alfred
    class << self
      attr_accessor :entries

      def get(key) = entries[key]
      def delete(key) = entries.delete(key)

      def set(key, value, ex:, nx: false)
        return false if nx && entries.key?(key)

        entries[key] = value if ex.positive?
        true
      end

      def delete_if_equals(key, value)
        delete(key) if get(key) == value
      end
    end
  end
end

require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/intake/configuration_operation'

class IntakeConfigurationOperationTest < Minitest::Test
  ID = 'f6fc64fe-6ecf-4c92-a1d8-f10ddd2241af'

  def setup
    Redis::Alfred.entries = {}
    @operation = JrcServiceDesk::Intake::ConfigurationOperation.new(3, 7, ID)
    @account = Object.new
    @member = Struct.new(:account, :user).new(@account, Object.new)
    inboxes = Object.new
    inboxes.define_singleton_method(:find) { |id| id == 13 ? id : raise('Unexpected inbox') }
    @account.define_singleton_method(:inboxes) { inboxes }
  end

  def test_readiness_is_queued_and_polls_return_only_the_authenticated_actors_result
    with_enqueue do
      assert_equal({ operation_id: ID, state: 'queued' },
                   @operation.start(kind: 'readiness', attributes: { inbox_id: '13' }, account: @account))
    end
    assert_equal({ 'operation_id' => ID, 'state' => 'queued' }, @operation.status)
    assert_nil JrcServiceDesk::Intake::ConfigurationOperation.new(4, 7, ID).status
    assert_nil JrcServiceDesk::Intake::ConfigurationOperation.new(3, 8, ID).status
    result = { ready: false, blockers: ['operation_not_permitted'], selection_count: 555 }
    service = Minitest::Mock.new.expect(:call, result, [], user_context: actor, attributes: { 'inbox_id' => '13' })
    perform_with(JrcServiceDesk::Intake::Readiness, service)
    assert_equal('completed', @operation.status.fetch('state'))
    assert_equal(result.transform_keys(&:to_s), @operation.status.fetch('result'))
  end

  def test_publication_runs_once_and_returns_the_actual_revision
    attributes = { 'inbox_id' => '13', 'expected_revision' => 4, 'remote_writes_enabled' => true }
    with_enqueue { @operation.start(kind: 'publish', attributes: attributes, account: @account) }
    record = Struct.new(:public_configuration).new({ id: '18', revision: 5, inbox_id: '13', remote_writes_enabled: true })
    service = Minitest::Mock.new.expect(:call, record, [], user_context: actor, attributes: attributes)
    perform_with(JrcServiceDesk::Intake::Publish, service)
    refute @operation.perform
    assert_equal(record.public_configuration.transform_keys(&:to_s), @operation.status.dig('result', 'record'))
  end

  def test_blocks_overlapping_operations_for_the_same_operator
    with_enqueue { @operation.start(kind: 'readiness', attributes: { inbox_id: '13' }, account: @account) }
    duplicate = JrcServiceDesk::Intake::ConfigurationOperation.new(3, 7, '1afb916c-3170-4cb1-a268-523483082e58')
    error = assert_raises(ArgumentError) { duplicate.start(kind: 'readiness', attributes: { inbox_id: '13' }, account: @account) }
    assert_equal('intake_operation_in_progress', error.message)
    assert_nil duplicate.status
  end

  def test_removed_operator_cannot_publish_from_the_queue
    attributes = { 'inbox_id' => '13', 'expected_revision' => 4, 'remote_writes_enabled' => true }
    with_enqueue { @operation.start(kind: 'publish', attributes: attributes, account: @account) }
    deleted_member = ->(**) { raise ActiveRecord::RecordNotFound }
    AccountUser.stub(:find_by!, deleted_member) { @operation.perform }
    assert_equal('failed', @operation.status.fetch('state'))
    assert_equal('intake_operation_not_authorized', @operation.status.fetch('error'))
    assert_nil @operation.status['result']
  end

  private

  def actor = { account: @account, user: @member.user, account_user: @member }

  def with_enqueue(&)
    JrcServiceDesk::IntakeConfigurationJob.stub(:perform_later, true, &)
  end

  def perform_with(service_class, service)
    AccountUser.stub(:find_by!, @member) do
      service_class.stub(:new, -> { service }) { @operation.perform }
    end
    service.verify
  end
end
