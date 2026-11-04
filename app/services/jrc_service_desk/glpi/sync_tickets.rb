# frozen_string_literal: true

class JrcServiceDesk::Glpi::SyncTickets
  def call(connection:, actor:, client: nil)
    @connection = connection
    @identity = { account: connection.account, user: actor.user, account_user: actor }
    @access = JrcServiceDesk::Glpi::Access.new(@identity).ready!
    raise Pundit::NotAuthorizedError unless @access.context.administrator? && @access.connection.id == connection.id

    @version = connection.lock_version
    @seen = {}
    @run = JrcServiceDesk::GlpiSyncRun.create!(account: connection.account, glpi_connection: connection,
      account_user: actor, connection_version: @version)
    if client
      collect(client)
    else
      JrcServiceDesk::Glpi::Client.new(connection).session { |remote| collect(remote) }
    end
    @run
  rescue JrcServiceDesk::Glpi::Error, Pundit::NotAuthorizedError => e
    raise unless @run

    @run.update!(state: 'failed', finished_at: Time.current,
                 coverage: @run.coverage.merge('error' => e.respond_to?(:code) ? e.code : 'access_revoked'))
    @run
  end

  private

  def collect(client)
    coverage = {}
    @access.entity_ids.each do |entity|
      coverage[entity.to_s] = collect_entity(client, entity)
      @run.update!(coverage: coverage)
    end
    current_access!
    complete = coverage.values.all? { |entry| entry['state'] == 'complete' }
    if complete
      JrcServiceDesk::GlpiTicketSnapshot.where(account_id: @connection.account_id, glpi_connection_id: @connection.id)
        .where.not(glpi_sync_run_id: @run.id).update_all(active: false)
    end
    @run.update!(state: complete ? 'complete' : 'partial', finished_at: Time.current)
  end

  def collect_entity(client, entity)
    observed = 0
    indexed = 0
    failures = []
    query = JrcServiceDesk::Glpi::TicketQuery.new(@access, 'entity_id' => entity)
    client.collection('search/Ticket/', query.parameters(offset: 0, size: 200)).each do |row|
      access = current_access!
      id = JrcServiceDesk::Input.id(row.fetch('2'))
      raise JrcServiceDesk::Glpi::Error.new('source_changed', 409) if @seen[id]

      @seen[id] = true
      observed += 1
      begin
        detail = client.get("Ticket/#{id}")
        actual_entity = JrcServiceDesk::Glpi::Identifiers.remote(detail.fetch('entities_id'))
        unless actual_entity == entity && JrcServiceDesk::Input.id(detail.fetch('id')) == id
          raise JrcServiceDesk::Glpi::Error.new('entity_mismatch', 409)
        end
        access.authorize_ticket!(client, detail)
        snapshot = JrcServiceDesk::GlpiTicketSnapshot.find_or_initialize_by(account: @connection.account,
          glpi_connection: @connection, remote_id: id)
        snapshot.update!(unit_id: access.unit_for(actual_entity), entity_id: actual_entity, connection_version: @version,
          payload: JrcServiceDesk::Glpi::Normalize.search(row).merge(JrcServiceDesk::Glpi::Normalize.detail(detail)),
          observed_at: Time.current, glpi_sync_run: @run, active: true)
        indexed += 1
      rescue JrcServiceDesk::Glpi::Error, Pundit::NotAuthorizedError, KeyError => e
        failures << (e.respond_to?(:code) ? e.code : e.is_a?(KeyError) ? 'invalid_response' : 'access_revoked')
      end
    end
    { 'state' => failures.empty? ? 'complete' : 'partial', 'observed' => observed, 'indexed' => indexed,
      'error' => failures.first, 'errors' => failures.tally }
  rescue JrcServiceDesk::Glpi::Error, Pundit::NotAuthorizedError, KeyError => e
    { 'state' => 'partial', 'observed' => observed, 'indexed' => indexed,
      'error' => e.respond_to?(:code) ? e.code : e.is_a?(KeyError) ? 'invalid_response' : 'access_revoked' }
  end

  def current_access!
    raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409) unless @connection.reload.lock_version == @version

    access = JrcServiceDesk::Glpi::Access.new(@identity).ready!
    raise Pundit::NotAuthorizedError unless access.context.administrator?

    access
  end
end
