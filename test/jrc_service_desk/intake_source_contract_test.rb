# frozen_string_literal: true

# Flat synthetic fixtures retain their stubs and complete scenario assertions.
# rubocop:disable Style/OneClassPerFile

require_relative 'intake_route_contract_test'
require_relative '../../app/services/jrc_service_desk/glpi/metadata_scope'
require_relative '../../app/services/jrc_service_desk/glpi/intake_sla'
require_relative '../../app/services/jrc_service_desk/intake/requester'

module Pundit; end
class Pundit::NotAuthorizedError < StandardError; end

# Scope and requester production classes run against read-only synthetic records.
class JrcServiceDesk::Glpi::Execute
  def fresh_access(access) = access
end

class IntakeSourceContractTest < Minitest::Test
  Access = Struct.new(:allowed) do
    def unit_for(entity)
      raise Pundit::NotAuthorizedError unless allowed.include?(entity)

      1
    end
  end
  Source = Struct.new(:rows, :lists, :reads) do
    def get(path)
      reads << path
      rows.fetch(path)
    end

    def collection(path, *_args)
      reads << path
      lists.fetch(path)
    end
  end

  def setup
    @access = Access.new([11])
    @source = Source.new({
                           'Entity/11' => { 'id' => 11, 'entities_id' => 7 }, 'Entity/7' => { 'id' => 7, 'entities_id' => 0 },
                           'SLA/13' => { 'id' => 13, 'entities_id' => 7, 'is_recursive' => 1, 'slms_id' => 2,
                                         'type' => 0, 'number_time' => 36, 'definition_time' => 'hour' },
                           'SLM/2' => { 'id' => 2, 'entities_id' => 7, 'is_recursive' => 1, 'calendars_id' => 0, 'use_ticket_calendar' => 0 },
                           'listSearchOptions/User/' => { '5' => { 'table' => 'glpi_useremails', 'field' => 'email' } },
                           'User/105' => { 'id' => 105, 'is_active' => 1 }
                         }, {
                           'search/User/' => [{ '2' => 105 }],
                           'User/105/UserEmail/' => [{ 'users_id' => 105, 'email' => 'request@example.invalid' }],
                           'User/105/Profile_User/' => [{ 'users_id' => 105, 'entities_id' => 7, 'is_recursive' => 1 }]
                         }, [])
    @sla = { 'id' => 13, 'purpose' => 'resolve', 'calendar_id' => 0 }
    @expected = { 'duration' => 36, 'unit' => 'hours' }
  end

  def test_parent_sla_applies_only_with_recursive_sla_and_slm
    assert JrcServiceDesk::Glpi::IntakeSla.new.validate!(access: @access, client: @source, entity_id: 11, mapping: @sla, expected: @expected)
    @source.rows['SLA/13']['is_recursive'] = 0
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::IntakeSla.new.validate!(access: @access, client: @source, entity_id: 11, mapping: @sla, expected: @expected)
    end
  end

  def test_hours_are_not_interchangeable_with_days
    @expected = { 'duration' => 7, 'unit' => 'days' }
    assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::IntakeSla.new.validate!(access: @access, client: @source, entity_id: 11, mapping: @sla, expected: @expected)
    end
  end

  def test_exact_email_requires_user_authorization_for_the_ticket_entity
    result = JrcServiceDesk::Intake::Requester.new.resolve!(access: @access, client: @source, entity_id: 11,
                                                            email: 'request@example.invalid', policy: 'email_only')
    assert_equal({ '_users_id_requester' => 105 }, result)
    @source.lists['User/105/Profile_User/'][0]['is_recursive'] = 0
    assert_raises(ArgumentError) do
      JrcServiceDesk::Intake::Requester.new.resolve!(access: @access, client: @source, entity_id: 11,
                                                     email: 'request@example.invalid', policy: 'email_only')
    end
  end

  def test_search_result_alone_does_not_establish_an_exact_email
    @source.lists['User/105/UserEmail/'][0]['email'] = 'other@example.invalid'
    result = JrcServiceDesk::Intake::Requester.new.resolve!(access: @access, client: @source, entity_id: 11,
                                                            email: 'request@example.invalid', policy: 'email_or_anonymous')
    assert_equal 0, result['_users_id_requester']
    assert_equal ['request@example.invalid'], result.dig('_users_id_requester_notif', 'alternative_email')
  end

  def test_ambiguous_authorized_users_never_pick_a_first_match
    @source.lists['search/User/'] << { '2' => 106 }
    @source.rows['User/106'] = { 'id' => 106, 'is_active' => 1 }
    @source.lists['User/106/UserEmail/'] = [{ 'users_id' => 106, 'email' => 'request@example.invalid' }]
    @source.lists['User/106/Profile_User/'] = [{ 'users_id' => 106, 'entities_id' => 11, 'is_recursive' => 0 }]
    error = assert_raises(ArgumentError) do
      JrcServiceDesk::Intake::Requester.new.resolve!(access: @access, client: @source, entity_id: 11,
                                                     email: 'request@example.invalid', policy: 'email_or_anonymous')
    end
    assert_equal 'intake_requester_ambiguous', error.message
  end

  def test_denied_email_catalogue_does_not_fallback_to_anonymous
    @source.rows['listSearchOptions/User/'] = {}
    assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Intake::Requester.new.resolve!(access: @access, client: @source, entity_id: 11,
                                                     email: 'request@example.invalid', policy: 'email_or_anonymous')
    end
  end
end

# rubocop:enable Style/OneClassPerFile
