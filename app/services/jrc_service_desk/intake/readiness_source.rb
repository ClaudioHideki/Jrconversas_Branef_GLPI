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
    operations << 'ticket.sla' if requires_sla?(candidates)
    operations.each do |operation|
      descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch(operation)
      alternatives = [descriptor[:source_right]] + descriptor[:source_alternatives]
      allowed = alternatives.any? { |right, mask| profile.fetch(right, 0).to_i.anybits?(mask) }
      raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) unless allowed
    end
  end

  def requires_sla?(candidates)
    @configuration.mappings.fetch('routes', []).any? { |route| route.fetch('slas', {}).any? } ||
      candidates.any? { |selection, _requesters| selection.dig('sla', 'unit') != 'none' }
  end

  def verify(access, client, selection, requester)
    provenance = { 'connection_id' => access.connection.id, 'connection_version' => access.connection.lock_version }
    contact_id = requester['policy_probe'] ? nil : requester.fetch('contact_id')
    demand = Candidate.new(selection, @configuration, contact_id, provenance)
    mapping = JrcServiceDesk::Intake::Mapping.new(demand)
    JrcServiceDesk::Glpi::Destination.new(mapping.destination).access!(@context.to_h)
    metadata = JrcServiceDesk::Glpi::MetadataScope.new(access: access, client: client, entity_id: mapping.route.fetch('entity_id'))
    metadata.authorize!('ITILCategory', client.get("ITILCategory/#{mapping.route.fetch('category_id')}"))
    verify_requester!(access, client, requester, mapping, metadata)
    mapping.preflight!(access: access, client: client, resolve_requester: !requester['policy_probe'])
  end

  def verify_requester!(access, client, requester, mapping, metadata)
    if requester['policy_probe']
      JrcServiceDesk::Intake::Requester.new.email_field(client)
      verify_anonymous_template!(access, client, mapping) if mapping.route['requester_policy'] == 'email_or_anonymous'
    else
      metadata.authorize!('User', client.get("User/#{mapping.requester_id}"))
    end
  end

  def verify_anonymous_template!(access, client, mapping)
    filters = { 'entity_id' => mapping.route.fetch('entity_id'), 'category_id' => mapping.route.fetch('category_id'),
                'type' => mapping.input['reason'] == 'bug' ? 1 : 2 }
    form = JrcServiceDesk::Glpi::TicketForm.new.call(access: access, client: client, filters: filters)
    if !form.fetch(:supported) || form.fetch(:required).include?('_users_id_requester') || form.fetch(:hidden).include?('_users_id_requester')
      raise JrcServiceDesk::Glpi::Error.new('intake_anonymous_template_incompatible', 422)
    end
  end
end
