# frozen_string_literal: true

# Flat synthetic fixtures retain their stubs and complete scenario assertions.
# rubocop:disable Rails/RefuteMethods

require 'minitest/autorun'
require 'active_support'
require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/access'
require 'active_support/core_ext/enumerable'

module JrcServiceDesk; end
module JrcServiceDesk::Intake; end
module JrcServiceDesk::Glpi; end
require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/glpi/identifiers'
require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/intake/sla_mapping'
require_relative '../../app/services/jrc_service_desk/intake/mapping'
require_relative '../../app/services/jrc_service_desk/glpi/operation_catalogue'
require_relative '../../app/services/jrc_service_desk/glpi/content'
require_relative '../../app/services/jrc_service_desk/glpi/command_input'

class IntakeRouteContractTest < Minitest::Test
  Demand = Struct.new(:normalized_input, :intake_configuration, :contact_id, :source_context)
  Config = Struct.new(:mappings)

  def setup
    @selection = { 'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
                   'profile' => nil, 'severity' => nil, 'subject_label' => 'Access', 'description' => 'Synthetic request',
                   'identifier_type' => 'cpf', 'identifier' => '00000000000', 'email' => 'request@example.invalid',
                   'sla' => { 'duration' => 36, 'unit' => 'hours' } }
    @route = @selection.slice(*JrcServiceDesk::Intake::Mapping::SELECTORS).merge(
      'entity_id' => 11, 'category_id' => 15, 'group_id' => 1, 'requester_policy' => 'mapped_contact',
      'request_type_id' => 8, 'creation_attributes' => true,
      'slas' => { 'own' => { 'id' => 12, 'purpose' => 'own', 'calendar_id' => 2, 'expected' => { 'duration' => 4, 'unit' => 'hours' } },
                  'resolve' => { 'id' => 13, 'purpose' => 'resolve', 'calendar_id' => 2 } }
    )
    @mappings = { 'routes' => [@route], 'requesters' => [{ 'contact_id' => 5, 'entity_id' => 11, 'user_id' => 105 }] }
    @demand = Demand.new(@selection, Config.new(@mappings), 5, {})
  end

  def test_new_route_creates_with_both_slas_group_origin_and_requester
    mapping = JrcServiceDesk::Intake::Mapping.new(@demand)
    values = mapping.attributes
    assert_equal 12, values['slas_id_tto']
    assert_equal 13, values['slas_id_ttr']
    assert_equal 1, values['_groups_id_assign']
    assert_equal 8, values['requesttypes_id']
    assert_equal 105, values['_users_id_requester']
    contract = JrcServiceDesk::Glpi::CommandInput.new(operation: 'ticket.create', target_id: nil, entity_id: 11, attributes: values)
    assert_equal 12, contract.input['slas_id_tto']
  end

  def test_improvement_keeps_own_deadline_without_inventing_resolution
    @selection['sla'] = { 'unit' => 'none' }
    @route['slas'].delete('resolve')
    values = JrcServiceDesk::Intake::Mapping.new(@demand).attributes
    assert_equal 12, values['slas_id_tto']
    refute values.key?('slas_id_ttr')
  end

  def test_approved_bug_route_sends_explicit_priority_with_neutral_axes
    { 'low' => 2, 'medium' => 3, 'high' => 4, 'critical' => 6 }.each do |severity, priority|
      @selection.merge!('reason' => 'bug', 'severity' => severity, 'impact_value' => 3, 'urgency_value' => 3)
      @route.merge!('reason' => 'bug', 'severity' => severity, 'priority' => priority)
      values = JrcServiceDesk::Intake::Mapping.new(@demand).attributes
      contract = JrcServiceDesk::Glpi::CommandInput.new(operation: 'ticket.create', target_id: nil, entity_id: 11, attributes: values)
      assert_equal priority, contract.input.fetch('priority')
      assert_equal [3, 3], contract.input.values_at('impact', 'urgency')
    end
  end

  def test_priority_is_not_added_to_legacy_routes
    values = JrcServiceDesk::Intake::Mapping.new(@demand).attributes
    refute values.key?('priority')
  end

  def test_invalid_route_priorities_and_non_bug_routes_are_rejected
    @route['priority'] = 6
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Mapping.new(@demand) }
    @selection.merge!('reason' => 'bug', 'severity' => 'critical')
    @route.merge!('reason' => 'bug', 'severity' => 'critical')
    [0, 7, '6', nil].each do |priority|
      @route['priority'] = priority
      assert_raises(ArgumentError) { JrcServiceDesk::Intake::Mapping.new(@demand) }
    end
    @route.merge!('priority' => 6, 'creation_attributes' => false)
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Mapping.new(@demand) }
  end

  def test_old_route_retains_separate_stage_contract
    @route.except!('slas', 'creation_attributes', 'request_type_id')
    @route['sla'] = { 'id' => 13, 'purpose' => 'resolve', 'calendar_id' => 2 }
    mapping = JrcServiceDesk::Intake::Mapping.new(@demand)
    assert_equal({ 'slas_id_ttr' => 13 }, mapping.sla_attributes)
    refute mapping.attributes.key?('_groups_id_assign')
    refute mapping.attributes.key?('slas_id_ttr')
  end

  def test_conflicting_old_and_new_slas_are_rejected
    @route['sla'] = { 'id' => 13, 'purpose' => 'resolve', 'calendar_id' => 2 }
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Mapping.new(@demand) }
  end

  def test_dual_sla_contract_requires_creation_attributes
    @route.delete('creation_attributes')
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Mapping.new(@demand) }
  end

  def test_anonymous_policy_must_be_explicitly_approved
    @route['requester_policy'] = 'email_or_anonymous'
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Mapping.new(@demand) }
  end

  def test_anonymous_notification_contract_is_strict_and_requires_zero_requester
    args = { 'name' => 'Synthetic', 'content' => 'Test', 'type' => 2, 'urgency' => 3, 'impact' => 3,
             '_users_id_requester' => 0, '_users_id_requester_notif' => {
               'use_notification' => [1], 'alternative_email' => ['request@example.invalid']
             } }
    contract = JrcServiceDesk::Glpi::CommandInput.new(operation: 'ticket.create', target_id: nil, entity_id: 11, attributes: args)
    assert_equal args['_users_id_requester_notif'], contract.input['_users_id_requester_notif']
    args['_users_id_requester'] = 105
    assert_raises(ArgumentError) do
      JrcServiceDesk::Glpi::CommandInput.new(operation: 'ticket.create', target_id: nil, entity_id: 11, attributes: args)
    end
  end
end

# rubocop:enable Rails/RefuteMethods
