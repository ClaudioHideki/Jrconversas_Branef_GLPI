# frozen_string_literal: true

# Flat synthetic fixtures retain their stubs and complete scenario assertions.
# rubocop:disable Style/OneClassPerFile, Rails/RefuteMethods

require_relative 'intake_source_contract_test'
require 'active_support/core_ext/object/deep_dup'
require_relative '../../app/services/jrc_service_desk/intake/readiness_source'
require_relative '../../app/services/jrc_service_desk/intake/readiness_source/read_only_source'
require_relative '../../app/services/jrc_service_desk/glpi/ticket_form'
require_relative '../../app/services/jrc_service_desk/canonical_json'

class JrcServiceDesk::Glpi::Destination
  def initialize(_destination); end
  def access!(_context) = true
end

class IntakeReadinessContractTest < IntakeSourceContractTest
  def test_readiness_forwards_recursive_entity_query_and_separates_cached_scopes
    calls = []
    source = Object.new
    source.define_singleton_method(:get) do |path, parameters = {}|
      calls << [path, parameters]
      { 'myentities' => parameters['is_recursive'] == 'true' ? [{ 'id' => 11 }] : [] }
    end
    cached = JrcServiceDesk::Intake::ReadinessSource::ReadOnlySource.new(source)
    assert_equal [{ 'id' => 11 }], cached.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
    assert_empty cached.get('getMyEntities/', 'is_recursive' => 'false').fetch('myentities')
    assert_equal [{ 'id' => 11 }], cached.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
    assert_equal [['getMyEntities/', { 'is_recursive' => 'true' }], ['getMyEntities/', { 'is_recursive' => 'false' }]], calls
  end

  def test_readiness_keeps_parameterless_get_contract
    source = Object.new
    source.define_singleton_method(:get) { |path| { 'id' => path.split('/').last.to_i } }
    cached = JrcServiceDesk::Intake::ReadinessSource::ReadOnlySource.new(source)
    assert_equal 190, cached.get('ITILCategory/190').fetch('id')
  end

  def test_email_policy_probe_does_not_need_a_contact_record
    selection = { 'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
                  'profile' => nil, 'severity' => nil, 'sla' => { 'duration' => 36, 'unit' => 'hours' } }
    route = selection.except('sla').merge('entity_id' => 11, 'category_id' => 15, 'group_id' => 1,
                                          'requester_policy' => 'email_only', 'requester_approved' => true, 'sla' => @sla)
    config = Struct.new(:mappings).new({ 'routes' => [route] })
    context = Object.new
    context.define_singleton_method(:to_h) { {} }
    @access.define_singleton_method(:connection) { Struct.new(:id, :lock_version).new(1, 0) }
    @access.define_singleton_method(:context) { self }
    @access.define_singleton_method(:capability?) { |_value| true }
    @source.rows['Group/1'] = { 'id' => 1, 'entities_id' => 7, 'is_recursive' => 1, 'is_assign' => 1 }
    @source.rows['ITILCategory/15'] = { 'id' => 15, 'entities_id' => 7, 'is_recursive' => 1 }
    service = JrcServiceDesk::Intake::ReadinessSource.new(context, config)
    service.send(:verify, @access, @source, selection, { 'policy_probe' => true })
    refute(@source.reads.any? { |path| path.start_with?('search/User') })
  end

  def test_improvement_own_sla_readiness_requires_update_right
    config = Struct.new(:mappings).new({ 'routes' => [{ 'slas' => { 'own' => { 'id' => 12 } } }] })
    @source.rows['getActiveProfile/'] = { 'active_profile' => { 'ticket' => 4 | 8192 } }
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Intake::ReadinessSource.new(nil, config).send(:authorize_operations!, @source,
                                                                    [[{ 'sla' => { 'unit' => 'none' } }, []]])
    end
    assert_equal 'operation_not_permitted', error.code
  end

  def test_creation_template_preserves_hidden_group_and_origin
    form = JrcServiceDesk::Glpi::TicketForm.new
    access = Struct.new(:context, :connection).new(Object.new, Struct.new(:id, :lock_version).new(1, 0))
    access.context.define_singleton_method(:capability?) { |_capability| true }
    form.instance_variable_set(:@access, access)
    form.instance_variable_set(:@entity, 11)
    template = { id: 1, revision: 'v1', required: ['_groups_id_assign'], hidden: %w[_groups_id_assign requesttypes_id],
                 predefined: { '_groups_id_assign' => 1, 'requesttypes_id' => 8 }, unsupported: [] }
    result = form.send(:build, template, 'category', 2, 0, { 'id' => 6 })
    assert result[:supported], result.inspect
    assert_includes result[:hidden], '_groups_id_assign'
    assert_includes result[:hidden], 'requesttypes_id'
  end

  def test_recursive_calendar_does_not_require_ancestor_ticket_access
    @sla['calendar_id'] = 2
    @source.rows['SLM/2']['calendars_id'] = 2
    @source.rows['Calendar/2'] = { 'id' => 2, 'entities_id' => 7, 'is_recursive' => 1 }
    @access.define_singleton_method(:context) { self }
    @access.define_singleton_method(:capability?) { |_value| true }
    assert JrcServiceDesk::Glpi::IntakeSla.new.validate!(access: @access, client: @source, entity_id: 11,
                                                         mapping: @sla, expected: @expected)
    assert_raises(Pundit::NotAuthorizedError) { @access.unit_for(7) }
  end
end

# rubocop:enable Style/OneClassPerFile, Rails/RefuteMethods
