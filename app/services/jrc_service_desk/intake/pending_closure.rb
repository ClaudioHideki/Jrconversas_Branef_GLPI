# frozen_string_literal: true

# Two source-confirmed commands. No local closure is substituted for a denied/uncertain GLPI action.
class JrcServiceDesk::Intake::PendingClosure
  def initialize(demand, control)
    @demand = demand
    @control = control
  end

  def call
    access = @control.access!
    @reference = reference(access)
    ticket = source_ticket(access)
    raise JrcServiceDesk::Glpi::Error.new('intake_source_not_waiting', 409) unless ticket['status'].to_i == 4

    @demand.update!(lifecycle_state: 'closing', completion_cause: 'no_response')
    @command = JrcServiceDesk::Glpi::AutomationCommand.new(authorizer: -> { @control.access! })
    return unless solution!(ticket)
    return unless close!

    complete!
  rescue JrcServiceDesk::Intake::PendingControl::Cancelled, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    fail_state('cancelled', 'intake_pending_cancelled')
  rescue JrcServiceDesk::Glpi::Error => e
    fail_state('needs_attention', e.code)
  rescue KeyError, ArgumentError, TypeError
    fail_state('needs_attention', 'intake_closure_invalid')
  end

  private

  def reference(access)
    mapping = JrcServiceDesk::Intake::Mapping.new(@demand)
    { 'account_id' => @demand.account_id, 'connection_id' => access.connection.id,
      'itemtype' => 'Ticket', 'remote_id' => @demand.remote_id, 'entity_id' => mapping.route.fetch('entity_id') }
  end

  def source_ticket(access)
    JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      JrcServiceDesk::Glpi::Reference.new(@reference).authorize!(access: access, client: client, operational: true)
    end
  end

  def solution!(ticket)
    apply('pending_solution', 'ticket.solve',
          { 'content' => 'Encerramento por ausência de retorno após 48 horas corridas do aviso entregue. Não representa solução técnica.' },
          ticket.fetch('date_mod'))
  end

  def close!
    ticket = source_ticket(@control.access!)
    raise JrcServiceDesk::Glpi::Error.new('intake_solution_unconfirmed', 409) unless ticket['status'].to_i == 5

    apply('pending_close', 'ticket.close', {}, ticket.fetch('date_mod'))
  end

  def apply(stage, operation, attributes, version)
    result = @command.call(user_context: @control.access!.context.to_h, reference: @reference,
                           operation: operation, attributes: attributes, expected_version: version,
                           idempotency_key: "intake/#{@demand.episode_key}/#{@demand.waiting_generation}/#{stage}")
    projection = result.stringify_keys.slice('id', 'state', 'error_code')
    @demand.update!(lifecycle_receipts: @demand.lifecycle_receipts.merge(stage => projection))
    return true if result[:state] == 'succeeded'

    state = @control.cancelled? ? 'cancelled' : 'needs_attention'
    fail_state(state, result[:error_code] || 'intake_closure_unconfirmed')
    false
  end

  def complete!
    # An inbound committed during remote I/O is not labelled an unattended success.
    return fail_state('needs_attention', 'intake_response_during_closure') if @control.cancelled?

    @demand.update!(lifecycle_state: 'closed_no_response', completed_at: Time.current,
                    waiting_generation: nil, waiting_deadline: nil, lifecycle_error_code: nil)
  end

  def fail_state(state, code)
    @demand.update!(lifecycle_state: state, waiting_generation: nil, waiting_deadline: nil, lifecycle_error_code: code)
  end
end
