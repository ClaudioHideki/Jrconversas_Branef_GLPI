# frozen_string_literal: true

class JrcServiceDesk::Intake::Notification
  def call(demand_id:, kind:, operator_context:, request_key:, human_confirmation: false)
    context = JrcServiceDesk::OperationalContext.new(operator_context)
    raise Pundit::NotAuthorizedError unless context.native_operator?

    demand = JrcServiceDesk::IntakeDemand.where(account_id: context.account.id).find(demand_id)
    JrcServiceDesk::Intake::LifecycleLock.call(demand.id) do
      demand.reload
      policy = JrcServiceDesk::Intake::NoticePolicy.new(demand, context.account_user)
      policy.authorize!
      prepare(demand, context.account_user, policy, kind, request_key, human_confirmation)
    end
  end

  def observe_message(message_id:)
    notice = JrcServiceDesk::IntakeNotification.find_by(message_id: message_id)
    return unless notice

    JrcServiceDesk::Intake::LifecycleLock.call(notice.intake_demand_id) do
      message = notice.message.reload
      return unless JrcServiceDesk::Intake::NoticePayload.match?(message, notice)
      return unless %w[delivered read].include?(message.status) && message.source_id.present? && notice.state != 'blocked'

      notice.update!(state: message.status, delivered_at: notice.delivered_at || Time.current)
      if notice.kind == 'pending_information'
        JrcServiceDesk::Intake::PendingInformation.new.start(demand_id: notice.intake_demand_id, notice_id: notice.id)
      end
      notice
    end
  end

  def complete(demand_id:, operator_context:, source_version:)
    JrcServiceDesk::Intake::HumanCompletion.new.call(demand_id: demand_id, operator_context: operator_context, source_version: source_version)
  end

  def self.eligible?(demand:, channel:)
    settings = demand.intake_configuration.reload.mappings.fetch('notifications', {})
    demand.lifecycle_state == 'completed_human' && demand.completion_cause == 'human' &&
      settings['enabled'] == true && settings['owner'] == 'jrc' && settings['channel'] == channel
  end

  private

  def prepare(demand, actor, policy, kind, request_key, confirmed)
    raise ArgumentError unless %w[pending_information survey].include?(kind)
    raise ArgumentError unless request_key.is_a?(String) && JrcServiceDesk::Intake::Submission::UUID.match?(request_key)

    scope = JrcServiceDesk::IntakeNotification.where(account: demand.account, intake_demand: demand, kind: kind)
    existing = kind == 'survey' ? scope.first : scope.find_by(request_key: request_key)
    if existing
      raise Pundit::NotAuthorizedError unless existing.account_user_id == actor.id

      return existing
    end
    template = template!(demand, policy.settings, kind)
    raise ArgumentError, 'intake_confirmation_required' if template['requires_confirmation'] == true && confirmed != true

    reason = policy.blocker
    reason ||= 'survey_not_eligible' if kind == 'survey' && !self.class.eligible?(demand: demand, channel: 'whatsapp')
    persist(demand, actor, policy, template, kind, request_key, reason)
  end

  def template!(demand, settings, kind)
    key = kind == 'survey' ? 'survey_template' : 'pending_information_template'
    matches = demand.intake_configuration.responses.select { |row| row['code'] == settings.fetch(key) }
    raise ArgumentError, 'intake_notice_template' unless matches.one? && matches.first['template'].is_a?(String)

    matches.first
  end

  def render(template, demand)
    values = { 'number' => demand.remote_id.to_s, 'customer_name' => demand.contact.name.to_s }
    body = template.fetch('template').gsub(/\{\{\s*(\w+)\s*\}\}/) { values.fetch(Regexp.last_match(1)) }
    raise ArgumentError, 'intake_notice_template' unless body.length.between?(1, 10_000) && !body.include?('{{')

    body
  end

  def persist(demand, actor, policy, template, kind, request_key, reason)
    notice = JrcServiceDesk::IntakeNotification.create!(
      account: demand.account, inbox: demand.inbox, conversation: demand.conversation, account_user: actor, intake_demand: demand,
      kind: kind, request_key: request_key, generation: SecureRandom.uuid, channel: 'whatsapp', template_code: template.fetch('code'),
      state: reason ? 'blocked' : 'queued', reason_code: reason, rendered_payload: render(template, demand),
      recipient_digest: policy.recipient_digest, source_snapshot: {
        'last_inbound_id' => demand.conversation.messages.incoming.maximum(:id),
        'input_digest' => JrcServiceDesk::CanonicalJson.digest(demand.normalized_input)
      }
    )
    if kind == 'pending_information' && reason.nil?
      demand.update!(lifecycle_state: 'awaiting_delivery', waiting_generation: notice.generation, pending_notice: notice,
        waiting_deadline: nil, waiting_control: {}, lifecycle_error_code: nil)
    end
    notice
  end
end
