# frozen_string_literal: true

# Flat synthetic fixtures retain their stubs and complete scenario assertions.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength

require_relative 'intake_delivery_test_helper'

class IntakeCreationAttributesIntegrationTest < IntakeDeliveryTest
  def test_new_route_sends_group_origin_and_both_deadlines_in_one_creation
    mappings = @delivery_configuration.mappings.deep_dup
    route = mappings.fetch('routes').first
    route.delete('sla')
    route.merge!('creation_attributes' => true, 'request_type_id' => 8,
                 'slas' => { 'own' => { 'id' => 31, 'purpose' => 'own', 'calendar_id' => 0,
                                        'expected' => { 'duration' => 4, 'unit' => 'hours' } },
                             'resolve' => { 'id' => 30, 'purpose' => 'resolve', 'calendar_id' => 0 } })
    configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 3, catalogue: @catalogue,
      mode: 'on_qualification', enabled: true, remote_writes_enabled: true, mappings: mappings
    )
    receipt = JrcServiceDesk::Intake::Submission.new.call(
      authority: @authority, conversation: @conversation,
      arguments: @arguments.merge(
        'configuration_id' => configuration.id, 'configuration_revision' => 3,
        'episode_key' => SecureRandom.uuid
      )
    )
    @demand = JrcServiceDesk::IntakeDemand.find(receipt.fetch(:id))
    @remote.rows['RequestType/8'] = { 'id' => 8, 'name' => 'WhatsApp' }
    @remote.rows['SLA/31'] = { 'id' => 31, 'entities_id' => 0, 'slms_id' => 40,
                               'type' => 1, 'number_time' => 4, 'definition_time' => 'hour' }
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'confirmed', result[:state], result.inspect
      assert_equal 1, @remote.writes.size
      verb, type, id, input = @remote.writes.first
      assert_equal [:post, 'Ticket', nil], [verb, type, id]
      assert_equal 20, input['_groups_id_assign']
      assert_equal 8, input['requesttypes_id']
      assert_equal 31, input['slas_id_tto']
      assert_equal 30, input['slas_id_ttr']
      assert_equal 2, input['status']
      JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 1, @remote.writes.size
    end
  end

  def test_unapproved_email_policy_is_rejected_before_any_source_write
    mappings = @delivery_configuration.mappings.deep_dup
    mappings.fetch('routes').first.merge!('requester_policy' => 'email_or_anonymous', 'requester_approved' => false)
    configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 3, catalogue: @catalogue,
      mode: 'on_qualification', enabled: true, remote_writes_enabled: true, mappings: mappings
    )
    receipt = JrcServiceDesk::Intake::Submission.new.call(
      authority: @authority, conversation: @conversation,
      arguments: @arguments.merge(
        'configuration_id' => configuration.id, 'configuration_revision' => 3,
        'episode_key' => SecureRandom.uuid
      )
    )
    @demand = JrcServiceDesk::IntakeDemand.find(receipt.fetch(:id))
    JrcServiceDesk::Glpi::Client.stub(:new, @remote) do
      result = JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
      assert_equal 'rejected', result[:state]
      assert_empty @remote.writes
    end
  end

  def test_direct_creation_rejects_first_response_sla_in_resolution_field
    @remote.rows['SLA/31'] = { 'id' => 31, 'entities_id' => 0, 'slms_id' => 40,
                               'type' => 1, 'number_time' => 4, 'definition_time' => 'hour' }
    result = JrcServiceDesk::Glpi::Execute.new(client_factory: ->(_) { @remote }).call(
      access: JrcServiceDesk::Glpi::Access.new(@identity), operation: 'ticket.create', target_id: nil, entity_id: 0,
      attributes: { 'name' => 'Synthetic request', 'content' => 'Synthetic description', 'type' => 2,
                    'urgency' => 3, 'impact' => 3, 'itilcategories_id' => 10, '_users_id_requester' => 77, 'slas_id_ttr' => 31 },
      idempotency_key: SecureRandom.uuid
    )
    assert_equal 'rejected', result[:state]
    assert_equal 'intake_sla_mismatch', result[:error_code]
    assert_empty @remote.writes
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
