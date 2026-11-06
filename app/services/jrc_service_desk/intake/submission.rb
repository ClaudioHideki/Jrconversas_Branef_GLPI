# frozen_string_literal: true

require 'digest'

# Called by an authenticated operator/service, never constructed from a contact's identity.
class JrcServiceDesk::Intake::Submission
  KEYS = %w[configuration_id configuration_revision episode_key phase input].freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  def call(authority:, conversation:, arguments:)
    values = JrcServiceDesk::Input.attributes(arguments, KEYS)
    raise ArgumentError, 'intake_episode' unless values['episode_key'].is_a?(String) && UUID.match?(values['episode_key'])
    raise ArgumentError, 'intake_phase' unless %w[qualified handoff].include?(values['phase'])

    JrcServiceDesk::IntakeDemand.transaction do
      authorized = authority.authorize!(lock: true)
      context = operational_context(authorized)
      target, configuration = resolve_target(context, conversation.id, values)
      persist(authority, context, target, configuration, values)
    end
  rescue KeyError
    raise ArgumentError, 'intake_required_field'
  end

  private

  def resolve_target(context, conversation_id, values)
    target = context.account.conversations.lock.find(conversation_id)
    configuration = JrcServiceDesk::IntakeConfiguration.where(account_id: context.account.id)
                                                       .find(JrcServiceDesk::Input.id(values.fetch('configuration_id')))
    authorize_configuration!(configuration, target, values.fetch('configuration_revision'))
    [target, configuration]
  end

  def operational_context(authority)
    member = authority.account.account_users.lock('FOR SHARE').find_by!(user_id: authority.user.id)
    context = JrcServiceDesk::OperationalContext.new(account: authority.account, user: authority.user, account_user: member)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.capability?(:tickets_create)

    context
  end

  def authorize_configuration!(configuration, conversation, revision)
    valid = configuration.enabled? && configuration.inbox_id == conversation.inbox_id &&
            configuration.revision == JrcServiceDesk::Input.version(revision)
    raise Pundit::NotAuthorizedError unless valid
  end

  def persist(authority, context, target, configuration, values)
    catalogue = JrcServiceDesk::Intake::Catalogue.new(configuration.catalogue)
    normalized = JrcServiceDesk::Intake::Input.new(catalogue).call(values.fetch('input'))
    fingerprint = JrcServiceDesk::CanonicalJson.digest(normalized.merge('configuration_id' => configuration.id))
    existing = JrcServiceDesk::IntakeDemand.lock.find_by(account_id: context.account.id, episode_key: values.fetch('episode_key'))
    return replay(existing, context, target, fingerprint, values.fetch('phase')) if existing

    demand = JrcServiceDesk::IntakeDemand.create!(
      account: context.account, inbox: target.inbox, contact: target.contact, conversation: target,
      account_user: context.account_user, intake_configuration: configuration, episode_key: values.fetch('episode_key'),
      normalized_input: normalized, fingerprint: fingerprint,
      source_context: JrcServiceDesk::Intake::Origin.capture(authority: authority, context: context,
        conversation: target, configuration: configuration),
      state: state_for(configuration, values.fetch('phase'))
    )
    demand.receipt(created: true)
  end

  def replay(existing, context, target, fingerprint, phase)
    raise Pundit::NotAuthorizedError unless existing.conversation_id == target.id && existing.account_user_id == context.account_user.id
    raise JrcServiceDesk::IdempotencyConflict unless existing.fingerprint == fingerprint

    existing.update!(state: state_for(existing.intake_configuration, phase)) if existing.state == 'qualified' && phase == 'handoff'
    existing.receipt
  end

  def state_for(configuration, phase)
    return 'test_only' unless configuration.remote_writes_enabled?
    return 'queued' if configuration.mode == 'on_qualification' || phase == 'handoff'

    'qualified'
  end
end
