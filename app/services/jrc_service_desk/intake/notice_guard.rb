# frozen_string_literal: true

class JrcServiceDesk::Intake::NoticeGuard
  def initialize(notice)
    @notice = notice
    @demand = notice.intake_demand.reload
  end

  def self.snapshot(demand)
    conversation = demand.conversation.reload
    { 'routing' => JrcFlowEffects::ControlRevision.snapshot(conversation).except('control_revision'),
      'binding' => JrcBroker::OutboundChannel.configuration(conversation.inbox),
      'control_state' => conversation.attributes.slice('status', 'assignee_id', 'team_id', 'assignee_agent_bot_id') }
  end

  def blocker
    policy = JrcServiceDesk::Intake::NoticePolicy.new(@demand, @notice.account_user)
    reason = policy.blocker
    return reason if reason

    JrcServiceDesk::Intake::Origin.new(@demand).authorize!(conversation_control: false)
    return 'recipient_changed' unless policy.recipient_digest == @notice.recipient_digest
    return 'notice_destination_changed' unless snapshot_matches?
    return 'intake_pending_cancelled' if stale_pending?

    nil
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcServiceDesk::Glpi::Error, ArgumentError, KeyError
    'notification_not_authorized'
  end

  private

  def snapshot_matches?
    self.class.snapshot(@demand) == @notice.source_snapshot.slice('routing', 'binding', 'control_state')
  end

  def stale_pending?
    @notice.kind == 'pending_information' && JrcServiceDesk::Intake::PendingControl.new(@demand, @notice).cancelled?
  end
end
