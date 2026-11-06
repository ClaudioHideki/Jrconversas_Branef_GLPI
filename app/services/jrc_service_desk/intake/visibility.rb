# frozen_string_literal: true

class JrcServiceDesk::Intake::Visibility
  def initialize(context)
    @context = JrcServiceDesk::OperationalContext.new(context)
  end

  def call(conversation)
    raise Pundit::NotAuthorizedError unless @context.native_operator? && @context.capability?(:tickets_view)

    scope = JrcServiceDesk::IntakeDemand.where(account_id: @context.account.id, conversation_id: conversation.id,
                                            inbox_id: conversation.inbox_id, contact_id: conversation.contact_id)
    scope.order(id: :desc).limit(30).filter_map do |demand|
      present(demand) if visible?(demand)
    end
  end

  def visible?(demand)
    return @context.administrator? unless demand.intake_configuration.remote_writes_enabled?

    access = JrcServiceDesk::Glpi::Access.new(@context.to_h).ready!
    entity = JrcServiceDesk::Intake::Mapping.new(demand).route.fetch('entity_id')
    unit = @context.unit_scope.find(access.unit_for(entity))
    @context.operational_unit_allowed?(unit)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError, JrcServiceDesk::Glpi::Error
    false
  end

  private

  def present(demand)
    demand.receipt.merge(
      selection: demand.normalized_input.except('identifier', 'identifier_type', 'email', 'description'),
      lifecycle_state: demand.lifecycle_state, completion_cause: demand.completion_cause,
      waiting_deadline: demand.waiting_deadline&.iso8601, lifecycle_error_code: demand.lifecycle_error_code,
      notifications: JrcServiceDesk::IntakeNotification.where(intake_demand: demand).order(:id).last(10).map(&:receipt),
      permissions: { notify: @context.capability?(:notifications_manage), complete: @context.capability?(:resolve) }
    )
  end
end
