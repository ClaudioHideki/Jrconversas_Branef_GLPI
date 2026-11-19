# frozen_string_literal: true

require 'json'

class JrcServiceDesk::Intake::ConfigurationOperation
  TTL = 30 * 60
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  ATTRIBUTE_KEYS = {
    'readiness' => JrcServiceDesk::Intake::Readiness::KEYS,
    'publish' => JrcServiceDesk::Intake::Publish::KEYS
  }.freeze

  def initialize(account_id, user_id, id)
    raise ArgumentError, 'invalid intake operation' unless id.is_a?(String) && UUID.match?(id)

    @account_id = account_id
    @user_id = user_id
    @id = id
    @active_key = "jrc:intake:operation:#{account_id}:#{user_id}"
    @key = "#{@active_key}:#{id}"
  end

  def start(kind:, attributes:, account:)
    values = JrcServiceDesk::Input.attributes(attributes, ATTRIBUTE_KEYS.fetch(kind))
    account.inboxes.find(JrcServiceDesk::Input.id(values.fetch('inbox_id')))
    draft = { state: 'queued', kind: kind, attributes: values }.to_json
    raise ArgumentError, 'intake_operation_in_progress' unless Redis::Alfred.set(@active_key, @id, nx: true, ex: TTL)

    enqueue(draft)
    { operation_id: @id, state: 'queued' }
  end

  def status
    entry&.slice('state', 'result', 'error')&.merge('operation_id' => @id)
  end

  def perform
    current = entry
    return unless current&.fetch('state') == 'queued'
    return unless Redis::Alfred.set("#{@key}:running", '1', nx: true, ex: TTL)

    complete(current)
  end

  private

  def enqueue(draft)
    Redis::Alfred.set(@key, draft, ex: TTL)
    raise ArgumentError, 'intake_queue_unavailable' unless JrcServiceDesk::IntakeConfigurationJob.perform_later(@account_id, @user_id, @id)
  rescue StandardError
    Redis::Alfred.delete(@key)
    Redis::Alfred.delete_if_equals(@active_key, @id)
    raise
  end

  def entry
    value = Redis::Alfred.get(@key)
    JSON.parse(value) if value
  end

  def complete(current)
    member = AccountUser.find_by!(account_id: @account_id, user_id: @user_id)
    context = { account: member.account, user: member.user, account_user: member }
    result = run(current.fetch('kind'), current.fetch('attributes'), context)
    store(state: 'completed', result: result)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    store(state: 'failed', error: 'intake_operation_not_authorized')
  rescue ArgumentError => e
    code = %w[intake_not_ready intake_revision_conflict].include?(e.message) ? e.message : 'intake_configuration_invalid'
    store(state: 'failed', error: code)
  rescue StandardError => e
    Rails.logger.warn("Intake operation failed account_id=#{@account_id} operation_id=#{@id} error_class=#{e.class}")
    store(state: 'failed', error: 'intake_operation_failed')
  ensure
    Redis::Alfred.delete_if_equals(@active_key, @id)
  end

  def run(kind, attributes, context)
    return JrcServiceDesk::Intake::Readiness.new.call(user_context: context, attributes: attributes) if kind == 'readiness'

    record = JrcServiceDesk::Intake::Publish.new.call(user_context: context, attributes: attributes)
    { record: record.public_configuration.slice(:id, :revision, :inbox_id, :remote_writes_enabled) }
  end

  def store(**result)
    Redis::Alfred.set(@key, result.to_json, ex: TTL)
  end
end
