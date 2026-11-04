# frozen_string_literal: true

require_relative 'glpi_commands_integration'

class GlpiTicketFormSource < GlpiCommandSource
  attr_accessor :profile_template, :metadata_denied, :on_template_read
  attr_reader :rules, :options

  def initialize
    super
    @profile_template = 10
    @rules = Hash.new { |hash, key| hash[key] = { 'Mandatory' => [], 'Hidden' => [], 'Predefined' => [] } }
    @template_reads = 0
    rows['Entity/0'] = { 'id' => 0, 'entities_id' => nil, 'tickettype' => 1,
      'tickettemplates_strategy' => 0, 'tickettemplates_id' => 0 }
    [10, 11, 20, 21].each do |id|
      rows["TicketTemplate/#{id}"] = { 'id' => id, 'name' => "Synthetic #{id}", 'entities_id' => 0, 'is_recursive' => 0, 'date_mod' => 'v1' }
    end
    rows['ITILCategory/7'] = { 'id' => 7, 'entities_id' => 0, 'is_recursive' => 0, 'is_incident' => 1, 'is_request' => 1,
      'tickettemplates_id_incident' => 20, 'tickettemplates_id_demand' => 21 }
    @options = { '1' => { 'table' => 'glpi_tickets', 'field' => 'name' },
      '21' => { 'table' => 'glpi_tickets', 'field' => 'content' }, '12' => { 'table' => 'glpi_tickets', 'field' => 'status' },
      '10' => { 'table' => 'glpi_tickets', 'field' => 'urgency' }, '11' => { 'table' => 'glpi_tickets', 'field' => 'impact' },
      '3' => { 'table' => 'glpi_tickets', 'field' => 'priority' }, '14' => { 'table' => 'glpi_tickets', 'field' => 'type' },
      '7' => { 'table' => 'glpi_itilcategories', 'field' => 'completename' },
      '4' => { 'table' => 'glpi_users', 'field' => 'name', 'linkfield' => 'users_id' },
      '13' => { 'table' => 'glpi_items_tickets', 'field' => 'items_id' } }
  end

  def get(path, *)
    raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403) if metadata_denied == path
    return options.deep_dup if path == 'listSearchOptions/Ticket/'
    if path == 'getActiveProfile/'
      return { 'active_profile' => { 'id' => 6, 'ticket' => 1048575, 'tickettemplates_id' => profile_template } }
    end
    if path.start_with?('TicketTemplate/')
      @template_reads += 1
      on_template_read&.call(@template_reads)
    end
    super
  end

  def collection(path, *)
    if (match = path.match(%r{\ATicketTemplate/(\d+)/TicketTemplate(Mandatory|Hidden|Predefined)Field/\z}))
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403) if metadata_denied == path

      return rules[match[1].to_i][match[2]].deep_dup
    end
    super
  end
end

class GlpiTicketFormTest < GlpiIntegrationTest
  def setup
    super
    @connection.update!(primary_source: true)
    @remote = GlpiTicketFormSource.new
    @access = JrcServiceDesk::Glpi::Access.new(@identity)
    @form = JrcServiceDesk::Glpi::TicketForm.new
    @execute = JrcServiceDesk::Glpi::Execute.new(client_factory: ->(_) { @remote })
  end

  def form(**filters)
    @form.call(access: @access, client: @remote, filters: { 'entity_id' => 0, 'type' => 1 }.merge(filters.transform_keys(&:to_s)))
  end

  def create(attributes = {}, **options)
    @execute.call(access: @access, operation: 'ticket.create', target_id: nil, entity_id: 0,
      attributes: { 'name' => 'Synthetic request', 'content' => 'Actual description' }.merge(attributes),
      idempotency_key: options.delete(:key) || SecureRandom.uuid, **options)
  end

  def test_template_priority_and_explicit_automatic_version_equivalence
    assert_equal 10, form[:template_id]
    assert_equal 'profile', form[:template_source]
    assert_equal form[:version], form(template_id: 10)[:version]
    assert_equal 20, form(category_id: 7)[:template_id]
    assert_equal 21, form(category_id: 7, type: 2)[:template_id]
    assert_equal 11, form(category_id: 7, template_id: 11)[:template_id]
    @remote.profile_template = 0
    @remote.rows['Entity/0']['tickettemplates_id'] = 11
    assert_equal 'entity', form[:template_source]
    assert_equal 11, form[:template_id]
    @remote.rows['Entity/0']['tickettemplates_id'] = 0
    assert_nil form[:template_id]
    assert_equal form[:version], form(template_id: 0)[:version]
  end

  def test_profile_predefined_type_and_category_reselect_category_template_without_its_type_category_rules
    @remote.rules[10]['Predefined'] = [{ 'id' => 1, 'tickettemplates_id' => 10, 'num' => 14, 'value' => '2' },
      { 'id' => 2, 'tickettemplates_id' => 10, 'num' => 7, 'value' => '7' }]
    @remote.rules[21]['Predefined'] = [{ 'id' => 3, 'tickettemplates_id' => 21, 'num' => 14, 'value' => '2' },
      { 'id' => 4, 'tickettemplates_id' => 21, 'num' => 10, 'value' => '5' }]
    policy = form
    assert_equal 21, policy[:template_id]
    assert_equal 1, policy[:type]
    assert_equal 0, policy[:category_id]
    assert_equal 5, policy[:predefined]['urgency']
  end

  def test_entity_inheritance_reads_only_its_ancestor_chain_and_honors_recursive_template_scope
    @remote.profile_template = 0
    @remote.rows['Entity/0'].merge!('tickettemplates_id' => 11)
    @remote.rows['Entity/8'] = { 'id' => 8, 'entities_id' => 0, 'tickettype' => -2,
      'tickettemplates_strategy' => -2, 'tickettemplates_id' => 0 }
    @remote.rows['TicketTemplate/11']['is_recursive'] = 1
    @connection.update!(entity_mappings: [{ 'entity_id' => 8, 'unit_id' => @unit.id }])
    policy = @form.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: @remote, filters: { 'entity_id' => 8, 'type' => 1 })
    assert_equal 11, policy[:template_id]
    @remote.rows['TicketTemplate/11']['is_recursive'] = 0
    assert_raises(Pundit::NotAuthorizedError) do
      @form.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: @remote, filters: { 'entity_id' => 8, 'type' => 1 })
    end
  end

  def test_source_metadata_denial_and_foreign_template_never_fall_back_to_no_model
    @remote.metadata_denied = 'TicketTemplate/10/TicketTemplateMandatoryField/'
    error = assert_raises(JrcServiceDesk::Glpi::Error) { form }
    assert_equal 403, error.http_status
    @remote.metadata_denied = nil
    @remote.rows['TicketTemplate/11']['entities_id'] = 999
    assert_raises(Pundit::NotAuthorizedError) { form(template_id: 11) }
    assert_empty @remote.writes
  end

  def test_predefined_hidden_and_required_are_typed_and_unsupported_required_fields_block_action
    @remote.rules[10]['Predefined'] = [{ 'id' => 1, 'tickettemplates_id' => 10, 'num' => 10, 'value' => '5' }]
    @remote.rules[10]['Hidden'] = [{ 'id' => 2, 'tickettemplates_id' => 10, 'num' => 10 }]
    @remote.rules[10]['Mandatory'] = [{ 'id' => 3, 'tickettemplates_id' => 10, 'num' => 7 }]
    policy = form
    assert_equal 5, policy[:predefined]['urgency']
    assert_includes policy[:hidden], 'urgency'
    assert_includes policy[:required], 'itilcategories_id'
    assert policy[:supported]
    rejected = create
    assert_equal 'rejected', rejected[:state]
    assert_equal 'required_fields_missing', rejected[:error_code]
    @remote.rules[10]['Mandatory'] << { 'id' => 4, 'tickettemplates_id' => 10, 'num' => 13 }
    policy = form
    refute policy[:supported]
    assert_includes policy[:unsupported_required], 'items_id'
    assert_equal 'template_fields_unsupported', create[:error_code]
    assert_empty @remote.writes
  end

  def test_primary_creation_applies_defaults_and_selector_without_overriding_allowed_edits
    @remote.rules[10]['Predefined'] = [{ 'id' => 1, 'tickettemplates_id' => 10, 'num' => 10, 'value' => '5' }]
    receipt = create({ 'impact' => 2 }, template_version: form[:version])
    assert_equal 'succeeded', receipt[:state], receipt.inspect
    payload = @remote.writes.last.last
    assert_equal 5, payload['urgency']
    assert_equal 2, payload['impact']
    assert_equal 10, payload['_tickettemplate']
    refute payload.key?('template_id')
    refute payload.key?('tickettemplates_id')
    assert_equal 'succeeded', create({ 'urgency' => 2 })[:state]
    assert_equal 2, @remote.writes.last.last['urgency']
    command = JrcServiceDesk::GlpiCommand.find(receipt[:id])
    assert_match(/\A[0-9a-f]{64}\z/, command.template_version)
    assert_equal 10, command.template_policy['template_id']
  end

  def test_hidden_override_and_unedited_mandatory_placeholder_are_rejected_before_write
    @remote.rules[10]['Hidden'] = [{ 'id' => 1, 'tickettemplates_id' => 10, 'num' => 10 }]
    @remote.rules[10]['Predefined'] = [{ 'id' => 2, 'tickettemplates_id' => 10, 'num' => 10, 'value' => '5' },
      { 'id' => 3, 'tickettemplates_id' => 10, 'num' => 21, 'value' => '&lt;p&gt;Describe your issue&lt;/p&gt;' }]
    @remote.rules[10]['Mandatory'] = [{ 'id' => 4, 'tickettemplates_id' => 10, 'num' => 21 }]
    assert_equal 'hidden_field_override', create({ 'urgency' => 2 })[:error_code]
    assert_equal 'required_content_unchanged', create({ 'content' => 'Describe your issue' })[:error_code]
    assert_empty @remote.writes
  end

  def test_changed_policy_before_send_and_stale_client_version_never_write
    version = form[:version]
    @remote.rows['TicketTemplate/10']['date_mod'] = 'v2'
    assert_equal 'template_changed', create({}, template_version: version)[:error_code]
    policy_reads = 0
    @remote.on_template_read = lambda do |_count|
      policy_reads += 1
      @remote.rows['TicketTemplate/10']['date_mod'] = 'v3' if policy_reads == 2
    end
    assert_equal 'template_changed', create[:error_code]
    assert_empty @remote.writes
  end

  def test_authorized_explicit_template_can_skip_denied_entity_default_metadata
    @remote.profile_template = 0
    @remote.metadata_denied = 'Entity/0'
    assert_raises(JrcServiceDesk::Glpi::Error) { form }
    assert_equal 10, form(template_id: 10)[:template_id]
    assert_equal 'explicit', form(template_id: 10)[:template_source]
  end

  def test_same_intent_key_replays_without_reloading_policy_or_duplicate_write
    receipt = create({}, key: 'same-form')
    assert_equal 'succeeded', receipt[:state]
    @remote.metadata_denied = 'TicketTemplate/10/TicketTemplateMandatoryField/'
    assert_equal receipt[:id], create({}, key: 'same-form')[:id]
    assert_equal 1, @remote.writes.size
    assert_raises(JrcServiceDesk::IdempotencyConflict) { create({ 'template_id' => 11 }, key: 'same-form') }
  end

  def test_legacy_connector_keeps_static_contract_without_loading_template_metadata
    @connection.update!(primary_source: false)
    @access = JrcServiceDesk::Glpi::Access.new(@identity)
    @remote.metadata_denied = 'getActiveProfile/'
    assert_raises(ArgumentError) { create }
    @remote.metadata_denied = 'TicketTemplate/10/TicketTemplateMandatoryField/'
    receipt = create({ 'type' => 1, 'urgency' => 3, 'impact' => 3 })
    assert_equal 'succeeded', receipt[:state]
    refute @remote.writes.last.last.key?('_tickettemplate')
  end
end
