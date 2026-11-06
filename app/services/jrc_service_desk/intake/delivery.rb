# frozen_string_literal: true

class JrcServiceDesk::Intake::Delivery
  def call(demand_id:)
    @demand = JrcServiceDesk::IntakeDemand.find(demand_id)
    with_delivery_lock do
      @demand.reload
      return @demand.receipt unless %w[queued sending].include?(@demand.state)
      return finish('indeterminate', 'intake_interrupted') if @demand.state == 'sending'

      deliver
    end
  end

  private

  def deliver
    perform_delivery
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    finish(@demand.remote_id ? 'partial' : 'rejected', 'intake_not_authorized')
  rescue JrcServiceDesk::Glpi::Error => e
    finish(@demand.remote_id ? 'partial' : 'rejected', e.code)
  rescue ArgumentError, KeyError, TypeError
    finish(@demand.remote_id ? 'partial' : 'rejected', 'intake_mapping_invalid')
  end

  def perform_delivery
    prepare!
    return @demand.receipt unless create_ticket!

    record_link!
    return @demand.receipt unless assignment! && sla!

    finish('confirmed')
  end

  def prepare!
    @origin = JrcServiceDesk::Intake::Origin.new(@demand)
    @mapping = JrcServiceDesk::Intake::Mapping.new(@demand)
    access = authorize!
    preflight!(access)
    @demand.update!(state: 'sending')
    @command = JrcServiceDesk::Glpi::AutomationCommand.new(authorizer: -> { authorize! })
  end

  def create_ticket!
    ticket = @command.create(user_context: authorize!.context.to_h, destination: @mapping.destination,
                             attributes: @mapping.attributes, idempotency_key: stage_key('ticket'))
    record_stage('ticket', ticket)
    unless ticket[:state] == 'succeeded'
      finish(ticket[:state] == 'rejected' ? 'rejected' : 'indeterminate', ticket[:error_code])
      return false
    end

    @demand.update!(remote_id: JrcServiceDesk::Input.id(ticket.fetch(:remote_id)))
    true
  end

  def authorize!
    identity = @origin.authorize!
    JrcServiceDesk::Glpi::Destination.new(@mapping.destination).access!(identity)
  end

  def preflight!(access)
    JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      @mapping.preflight!(access: access, client: client)
    end
    authorize!
  end

  def reference
    { 'account_id' => @demand.account_id, 'connection_id' => @mapping.destination.fetch('connection_id'),
      'itemtype' => 'Ticket', 'remote_id' => @demand.remote_id, 'entity_id' => @mapping.route.fetch('entity_id') }
  end

  def record_link!
    access = authorize!
    raise Pundit::NotAuthorizedError unless access.context.capability?(:conversations_link)

    record = JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      JrcServiceDesk::Glpi::Reference.new(reference).record!(access: access, client: client, operational: true)
    end
    authorize!
    link = JrcServiceDesk::GlpiReferenceLink.find_or_create_by!(account: @demand.account, glpi_reference: record,
                                                                conversation: @demand.conversation, account_user: @demand.account_user, unit_id: record.unit_id)
    record_stage('link', id: link.id.to_s, state: 'succeeded')
  end

  def assignment!
    apply_stage('assignment', 'ticket.assign', '_groups_id_assign' => @mapping.route.fetch('group_id'))
  end

  def sla!
    unless (attributes = @mapping.sla_attributes)
      record_stage('sla', state: 'not_required')
      return true
    end
    preflight!(authorize!)
    apply_stage('sla', 'ticket.sla', attributes)
  end

  def apply_stage(stage, operation, attributes)
    result = @command.call(user_context: authorize!.context.to_h, reference: reference,
                           operation: operation, attributes: attributes, idempotency_key: stage_key(stage))
    record_stage(stage, result)
    return true if result[:state] == 'succeeded'

    finish('partial', result[:error_code])
    false
  end

  def record_stage(name, receipt)
    projection = receipt.stringify_keys.slice('id', 'state', 'error_code')
    @demand.update!(delivery_receipts: @demand.delivery_receipts.merge(name => projection))
  end

  def finish(state, code = nil)
    @demand.update!(state: state, error_code: code)
    @demand.receipt
  end

  def stage_key(stage) = "intake/#{@demand.episode_key}/#{stage}"

  # A session lock serializes workers; remote IO never runs in an audit transaction.
  def with_delivery_lock
    key = Digest::SHA256.hexdigest("service-desk-intake/#{@demand.id}")[0, 15].to_i(16)
    JrcServiceDesk::IntakeDemand.connection_pool.with_connection do |connection|
      connection.execute("SELECT pg_advisory_lock(#{key})")
      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
