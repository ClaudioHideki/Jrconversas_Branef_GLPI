# frozen_string_literal: true

class JrcServiceDesk::Intake::NoticePreparation
  def initialize(demand, actor)
    @demand = demand
    @actor = actor
    @policy = JrcServiceDesk::Intake::NoticePolicy.new(demand, actor)
  end

  def call(kind:, request_key:, confirmed:)
    raise ArgumentError unless %w[pending_information survey].include?(kind)
    raise ArgumentError unless request_key.is_a?(String) && JrcServiceDesk::Intake::Submission::UUID.match?(request_key)

    previous = existing(kind, request_key)
    return previous if previous

    template = template!(kind)
    raise ArgumentError, 'intake_confirmation_required' if template['requires_confirmation'] == true && confirmed != true

    reason = @policy.blocker
    reason ||= 'survey_not_eligible' if kind == 'survey' && !JrcServiceDesk::Intake::Notification.eligible?(demand: @demand, channel: 'whatsapp')
    persist(template, kind: kind, request_key: request_key, reason: reason)
  end

  private

  def existing(kind, key)
    scope = JrcServiceDesk::IntakeNotification.where(account: @demand.account, intake_demand: @demand, kind: kind)
    previous = kind == 'survey' ? scope.first : scope.find_by(request_key: key)
    raise Pundit::NotAuthorizedError if previous && previous.account_user_id != @actor.id

    previous
  end

  def template!(kind)
    key = kind == 'survey' ? 'survey_template' : 'pending_information_template'
    matches = @demand.intake_configuration.responses.select { |row| row['code'] == @policy.settings.fetch(key) }
    raise ArgumentError, 'intake_notice_template' unless matches.one? && matches.first['template'].is_a?(String)

    matches.first
  end

  def render(template)
    values = { 'number' => @demand.remote_id.to_s, 'customer_name' => @demand.contact.name.to_s }
    body = template.fetch('template').gsub(/\{\{\s*(\w+)\s*\}\}/) { values.fetch(Regexp.last_match(1)) }
    raise ArgumentError, 'intake_notice_template' unless body.length.between?(1, 10_000) && body.exclude?('{{')

    body
  end

  def source_snapshot
    JrcServiceDesk::Intake::NoticeGuard.snapshot(@demand).merge(
      'last_inbound_id' => @demand.conversation.messages.incoming.maximum(:id),
      'input_digest' => JrcServiceDesk::CanonicalJson.digest(@demand.normalized_input)
    )
  end

  def persist(template, kind:, request_key:, reason:)
    @demand.with_lock do
      notice = JrcServiceDesk::IntakeNotification.create!(
        account: @demand.account, inbox: @demand.inbox, conversation: @demand.conversation, account_user: @actor, intake_demand: @demand,
        kind: kind, request_key: request_key, generation: SecureRandom.uuid, channel: 'whatsapp', template_code: template.fetch('code'),
        state: reason ? 'blocked' : 'queued', reason_code: reason, rendered_payload: render(template),
        recipient_digest: @policy.recipient_digest, source_snapshot: source_snapshot
      )
      awaiting_delivery(notice) if kind == 'pending_information' && reason.nil?
      notice
    end
  end

  def awaiting_delivery(notice)
    @demand.update!(lifecycle_state: 'awaiting_delivery', waiting_generation: notice.generation, pending_notice: notice,
                    waiting_deadline: nil, waiting_control: {}, lifecycle_error_code: nil)
  end
end
