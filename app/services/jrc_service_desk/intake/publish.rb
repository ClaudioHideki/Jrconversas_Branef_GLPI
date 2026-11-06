# frozen_string_literal: true

class JrcServiceDesk::Intake::Publish
  KEYS = %w[inbox_id expected_revision catalogue mappings responses mode remote_writes_enabled].freeze

  def call(user_context:, attributes:)
    context = JrcServiceDesk::OperationalContext.new(user_context)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.administrator? && context.capability?(:settings_view)

    values = JrcServiceDesk::Input.attributes(attributes, KEYS)
    verify_source!(context, values) if values['remote_writes_enabled'] == true
    JrcServiceDesk::IntakeConfiguration.transaction do
      inbox = context.account.inboxes.lock.find(JrcServiceDesk::Input.id(values.fetch('inbox_id')))
      previous = next_revision!(context.account, inbox, values.fetch('expected_revision'))
      create_configuration(context, inbox, previous + 1, values)
    end
  end

  private

  def verify_source!(context, values)
    readiness = JrcServiceDesk::Intake::Readiness.new.call(user_context: context.to_h, attributes: values.except('expected_revision'))
    raise ArgumentError, 'intake_not_ready' unless readiness.fetch(:ready)
  end

  def next_revision!(account, inbox, expected)
    scope = JrcServiceDesk::IntakeConfiguration.where(account_id: account.id, inbox_id: inbox.id)
    previous = scope.maximum(:revision) || 0
    raise ArgumentError, 'intake_revision_conflict' unless previous == JrcServiceDesk::Input.version(expected)

    scope.where(current: true).find_each { |record| record.update!(current: false) }
    previous
  end

  def create_configuration(context, inbox, revision, values)
    JrcServiceDesk::IntakeConfiguration.create!(
      account: context.account, inbox: inbox, created_by_account_user: context.account_user, revision: revision,
      catalogue: values.fetch('catalogue'), mappings: values.fetch('mappings'), responses: values.fetch('responses'),
      mode: values.fetch('mode'), remote_writes_enabled: values.fetch('remote_writes_enabled'), enabled: true, current: true
    )
  end
end
