# frozen_string_literal: true

class JrcServiceDesk::Intake::PendingControl
  class Cancelled < StandardError; end

  def initialize(demand, notice)
    @demand = demand
    @notice = notice
  end

  def snapshot
    target = @demand.conversation.reload
    { 'routing' => JrcFlowEffects::ControlRevision.snapshot(target), 'status' => target.status,
      'assignee_id' => target.assignee_id, 'team_id' => target.team_id, 'agent_bot_id' => target.assignee_agent_bot_id,
      'input_digest' => JrcServiceDesk::CanonicalJson.digest(@demand.normalized_input) }
  end

  def cancelled?
    @demand.reload
    return true unless @demand.intake_configuration.reload.enabled?
    return true unless @demand.pending_notice_id == @notice.id && @demand.waiting_generation == @notice.generation
    return true unless %w[awaiting_delivery awaiting_information closing].include?(@demand.lifecycle_state)
    return true if inbound_after_request?
    return true unless @notice.source_snapshot['input_digest'] == JrcServiceDesk::CanonicalJson.digest(@demand.normalized_input)
    return true if @demand.waiting_control.present? && @demand.waiting_control != snapshot

    false
  end

  def access!
    raise Cancelled if cancelled?

    identity = JrcServiceDesk::Intake::Origin.new(@demand).authorize!(conversation_control: false)
    mapping = JrcServiceDesk::Intake::Mapping.new(@demand)
    JrcServiceDesk::Glpi::Destination.new(mapping.destination).access!(identity)
  end

  private

  def inbound_after_request?
    boundary = @notice.source_snapshot.fetch('last_inbound_id', nil) || 0
    @demand.conversation.messages.where(account_id: @demand.account_id).incoming.where('id > ?', boundary).exists?
  end
end
