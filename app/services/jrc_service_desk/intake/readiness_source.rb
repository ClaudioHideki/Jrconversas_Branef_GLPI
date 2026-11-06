# frozen_string_literal: true

# GET-only bounded preflight. Per-request caching does not outlive the source session.
class JrcServiceDesk::Intake::ReadinessSource
  Candidate = Struct.new(:normalized_input, :intake_configuration, :contact_id, :source_context)

  def initialize(context, configuration)
    @context = context
    @configuration = configuration
  end

  def call(candidates)
    access = JrcServiceDesk::Glpi::Access.new(@context.to_h).ready!
    raise Pundit::NotAuthorizedError unless JrcBroker::OutboundChannel.available?(@configuration.inbox)

    JrcServiceDesk::Glpi::Client.new(access.connection).session(read_only: true) do |source|
      client = ReadOnlySource.new(source)
      authorize_operations!(client, candidates)
      candidates.each do |selection, requesters|
        requesters.each { |requester| verify(access, client, selection, requester) }
      end
    end
  end

  private

  def authorize_operations!(client, candidates)
    profile = client.get('getActiveProfile/').fetch('active_profile')
    operations = %w[ticket.create ticket.assign]
    operations << 'ticket.sla' if candidates.any? { |selection, _requesters| selection.dig('sla', 'unit') != 'none' }
    operations.each do |operation|
      descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch(operation)
      alternatives = [descriptor[:source_right]] + descriptor[:source_alternatives]
      allowed = alternatives.any? { |right, mask| (profile.fetch(right, 0).to_i & mask).positive? }
      raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) unless allowed
    end
  end

  def verify(access, client, selection, requester)
    provenance = { 'connection_id' => access.connection.id, 'connection_version' => access.connection.lock_version }
    demand = Candidate.new(selection, @configuration, requester.fetch('contact_id'), provenance)
    mapping = JrcServiceDesk::Intake::Mapping.new(demand)
    JrcServiceDesk::Glpi::Destination.new(mapping.destination).access!(@context.to_h)
    metadata = JrcServiceDesk::Glpi::MetadataScope.new(access: access, client: client, entity_id: mapping.route.fetch('entity_id'))
    metadata.authorize!('ITILCategory', client.get("ITILCategory/#{mapping.route.fetch('category_id')}"))
    metadata.authorize!('User', client.get("User/#{mapping.requester_id}"))
    mapping.preflight!(access: access, client: client)
  end
end
