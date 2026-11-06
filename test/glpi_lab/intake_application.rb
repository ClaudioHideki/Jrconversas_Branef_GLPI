# frozen_string_literal: true

# Flat synthetic integration scenarios use plain Minitest assertions.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Rails/RefuteMethods

# Real GLPI 10 API, synthetic requester and independent readbacks; no customer network.
class GlpiIntakeLaboratoryTest < IntakeIntegrationTest
  def setup
    super
    @fixtures = GlpiLabEvidence::FIXTURES
    @intake = @fixtures.fetch('intake')
    @connection.update!(base_url: 'https://glpi.example.invalid:14443/apirest.php', primary_source: true,
      app_token: @fixtures.fetch('app_token'), user_token: @fixtures.fetch('user_token'))
    JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
    @delivery_configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 2, catalogue: @catalogue,
      mode: 'on_qualification', enabled: true, remote_writes_enabled: true,
      mappings: { 'routes' => [{ 'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
        'profile' => 'requester', 'severity' => nil, 'entity_id' => 0, 'category_id' => @intake.fetch('category_id'),
        'group_id' => @intake.fetch('group_id'), 'requester_policy' => 'mapped_contact',
        'sla' => { 'id' => @intake.fetch('sla_id'), 'purpose' => 'resolve', 'calendar_id' => 0 } }],
        'requesters' => [{ 'contact_id' => @conversation.contact_id, 'entity_id' => 0, 'user_id' => @intake.fetch('requester_id') }] }
    )
  end

  def test_actual_creation_queue_sla_and_replay_keep_one_remote_protocol
    arguments = @arguments.merge('configuration_id' => @delivery_configuration.id, 'configuration_revision' => 2)
    intent = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: arguments)
    result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: intent.fetch(:id))
    assert_equal 'confirmed', result.fetch(:state), result.slice(:state, :error_code, :stages).to_json
    id = result.fetch(:remote_id)
    JrcServiceDesk::Glpi::Client.new(@connection).session do |client|
      ticket = client.get("Ticket/#{id}")
      assert_equal 0, ticket.fetch('entities_id').to_i
      assert_equal @intake.fetch('category_id'), ticket.fetch('itilcategories_id').to_i
      assert_equal @intake.fetch('sla_id'), ticket.fetch('slas_id_ttr').to_i
      assert ticket.fetch('time_to_resolve').present?
      assert_in_delta 5.days.to_i, Time.zone.parse(ticket.fetch('time_to_resolve')) - Time.zone.parse(ticket.fetch('date')), 1
      requesters = client.collection("Ticket/#{id}/Ticket_User/").select { |actor| actor['type'].to_i == 1 }
      assert requesters.any? { |actor| actor['users_id'].to_i == @intake.fetch('requester_id') }
      refute requesters.any? { |actor| actor['users_id'].to_i == @fixtures.fetch('technical_user_id') }
      assigned = client.collection("Ticket/#{id}/Group_Ticket/").any? do |actor|
        actor['type'].to_i == 2 && actor['groups_id'].to_i == @intake.fetch('group_id')
      end
      assert assigned
    end
    before = GlpiLabTransport::ITEM_MUTATIONS.dup
    replay = JrcServiceDesk::Intake::Delivery.new.call(demand_id: intent.fetch(:id))
    assert_equal id, replay.fetch(:remote_id)
    assert_equal before, GlpiLabTransport::ITEM_MUTATIONS
    assert_equal 1, JrcServiceDesk::GlpiReferenceLink.where(account: @account, conversation: @conversation).count
    assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
    command = JrcServiceDesk::GlpiCommand.find(result.dig(:stages, 'sla', 'id'))
    GlpiLabEvidence::RESULTS['ticket.sla'] = command.receipt.slice(:state, :error_code, :technical_user_id, :itemtype)
    GlpiLabEvidence::CHECKS << 'actual intake: one ticket, separate requester, group, five native days, replay without write'
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Rails/RefuteMethods
