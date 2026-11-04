# frozen_string_literal: true

class JrcServiceDesk::Glpi::Reconcile
  def initialize(client_factory: ->(connection) { JrcServiceDesk::Glpi::Client.new(connection) })
    @client_factory = client_factory
    @executor = JrcServiceDesk::Glpi::Execute.new(client_factory: client_factory)
  end

  # Reconciliation is read-only at the source. An ambiguous POST is never resent.
  def call(access:, command:, remote_id: nil)
    access = @executor.fresh_access(access)
    raise Pundit::NotAuthorizedError unless command.account_id == access.context.account.id && command.glpi_connection_id == access.connection.id
    unless command.account_user_id == access.context.account_user.id || access.context.administrator?
      raise Pundit::NotAuthorizedError
    end
    access.unit_for(command.entity_id)
    descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch(command.operation)
    @executor.authorize_local!(access, descriptor)
    @executor.with_object_lock(command) do
      command.reload
      return command.receipt if command.state == 'succeeded'
      raise JrcServiceDesk::IdempotencyConflict unless %w[sending indeterminate].include?(command.state)
      if command.connection_version && command.connection_version != access.connection.lock_version
        raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
      end
      id = JrcServiceDesk::Input.id(remote_id || command.remote_id || command.target_id)
      if descriptor[:verb] != 'post' && id != command.target_id
        raise ArgumentError
      end
      @client_factory.call(access.connection).session do |client|
        # A missing record after an ambiguous DELETE is not proof that this command deleted it.
        raise JrcServiceDesk::Glpi::Error.new('reconciliation_unverifiable', 409) if descriptor[:verb] == 'delete'

        row = client.get("#{command.itemtype}/#{id}")
        @executor.verify_id!(row, id)
        if descriptor[:verb] == 'post' && !command.remote_id
          correlated = %w[content answer].any? do |field|
            JrcServiceDesk::Glpi::Normalize.text(row[field]).include?(command.correlation_marker)
          end
          raise JrcServiceDesk::Glpi::Error.new('reconciliation_unverifiable', 409) unless correlated
        end
        if command.request_payload
          @executor.authorize_objects!(access, client, command, descriptor)
          result = @executor.verify_readback!(access, client, command, descriptor, id)
        else
          # Receipts created before the extended schema retain their correlation proof.
          @executor.verify_entity!(row, command.entity_id)
          access.authorize_ticket!(client, row)
          result = { 'verified' => true, 'remote_id' => id.to_s, 'legacy_correlation' => true }
        end
        command.update!(state: 'succeeded', remote_id: id, error_code: nil, result: result)
      end
    end
    command.receipt
  end
end
