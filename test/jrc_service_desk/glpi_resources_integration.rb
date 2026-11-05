# frozen_string_literal: true

require_relative 'glpi_test_helper'

class GlpiResourcesTest < GlpiIntegrationTest
  def test_asset_candidates_are_typed_scoped_searchable_and_distinct_from_associations
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    client.expect(:collection, [{ 'id' => 201, 'entities_id' => 0, 'name' => 'Synthetic laptop' },
                                { 'id' => 202, 'entities_id' => 999, 'name' => 'Foreign laptop' }], ['Computer/', { 'sort' => 'id', 'order' => 'ASC' }])
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    result = JrcServiceDesk::Glpi::AssetQuery.new.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: client,
      filters: { 'ticket_id' => 101, 'asset_type' => 'Computer', 'search' => 'laptop' })
    assert_equal [201], result[:items].map { |item| item['id'] }
    assert_equal 'Computer', result[:items].first['itemtype']
    refute result[:items].first.key?('tickets_id')
    client.verify
  end

  def test_asset_detail_rejects_foreign_unmapped_and_untyped_targets
    %w[Computer Profile].each do |type|
      client = Object.new
      def client.get(path)
        path == 'Ticket/101' ? { 'id' => 101, 'entities_id' => 0 } : { 'id' => 201, 'entities_id' => 999, 'name' => 'Foreign' }
      end
      assert_raises(Pundit::NotAuthorizedError, ArgumentError) do
        JrcServiceDesk::Glpi::AssetQuery.new.find(access: JrcServiceDesk::Glpi::Access.new(@identity), client: client, id: 201,
          filters: { 'ticket_id' => 101, 'asset_type' => type })
      end
    end
  end

  def test_asset_source403_is_explicit_and_context_is_required
    query = JrcServiceDesk::Glpi::AssetQuery.new
    client = Object.new
    def client.get(*) = { 'id' => 101, 'entities_id' => 0 }
    def client.collection(*) = raise(JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403))
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      query.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: client,
        filters: { 'ticket_id' => 101, 'asset_type' => 'Computer' })
    end
    assert_equal 403, error.http_status
    assert_raises(KeyError) { query.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: client, filters: { 'asset_type' => 'Computer' }) }
  end

  def test_complete_history_uses_pagination_and_does_not_cut_at_one_hundred
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    rows = (1..205).map { |id| { 'id' => id, 'items_id' => 101, 'itemtype' => 'Ticket', 'content' => 'Synthetic', 'is_private' => 0 } }
    client.expect(:collection, rows, ['Ticket/101/ITILFollowup/'])
    result = JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
      client: client, kind: 'followups', ticket_id: 101)
    assert_equal 205, result.fetch(:items).size
    assert result.fetch(:coverage).fetch(:complete)
    client.verify
  end

  def test_foreign_parent_in_a_nested_response_is_denied
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    client.expect(:collection, [{ 'id' => 1, 'tickets_id' => 999, 'content' => 'Foreign' }], ['Ticket/101/TicketTask/'])
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
        client: client, kind: 'tasks', ticket_id: 101)
    end
  end

  def test_a_remote_catalogue_denial_stays_a_denial
    client = Object.new
    def client.collection(*)
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403)
    end
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::ResourceQuery.new.call(access: JrcServiceDesk::Glpi::Access.new(@identity),
        client: client, kind: 'categories', filters: {})
    end
    assert_equal 403, error.http_status
  end

  def test_problem_in_unmapped_entity_is_denied
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 201, 'entities_id' => 999, 'name' => 'Foreign' }, ['Problem/201'])
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::ResourceQuery.new.find(access: JrcServiceDesk::Glpi::Access.new(@identity),
        client: client, kind: 'problems', id: 201)
    end
  end

  def test_knowledge_requires_visibility_in_an_authorized_entity
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 301, 'name' => 'Private article' }, ['KnowbaseItem/301'])
    client.expect(:collection, [{ 'id' => 5, 'entities_id' => 999, 'knowbaseitems_id' => 301 }], ['KnowbaseItem/301/Entity_KnowbaseItem/'])
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::ResourceQuery.new.find(access: JrcServiceDesk::Glpi::Access.new(@identity),
        client: client, kind: 'knowledge', id: 301)
    end
  end

  def test_operations_are_allowlisted_and_not_an_administrative_proxy
    descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch('ticket.update')
    assert_equal 'Ticket', descriptor.fetch(:type)
    assert_raises(KeyError) { JrcServiceDesk::Glpi::OperationCatalogue.fetch('user.update') }
    assert_raises(KeyError) { JrcServiceDesk::Glpi::OperationCatalogue.fetch('../../Profile') }
  end

  def test_source_denial_is_distinct_from_connector_support
    client = Minitest::Mock.new
    client.expect(:get, { 'active_profile' => { 'id' => 6, 'ticket' => 0 } }, ['getActiveProfile/'])
    result = JrcServiceDesk::Glpi::Capabilities.new.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: client)
    operation = result.fetch(:operations).find { |row| row[:operation] == 'ticket.update' }
    assert operation.fetch(:supported)
    refute operation.fetch(:source_allowed)
    assert operation.fetch(:source_checked)
    refute operation.fetch(:homologated)
  end

  def test_a_reused_reader_cannot_reuse_a_parent_from_another_account
    query = JrcServiceDesk::Glpi::ResourceQuery.new
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    client.expect(:collection, [], ['Ticket/101/ITILFollowup/'])
    query.related(access: JrcServiceDesk::Glpi::Access.new(@identity), client: client, kind: 'followups', ticket_id: 101)
    other = Account.create!(name: 'Foreign reader', status: 'active')
    other.enable_features!('jrc_service_desk')
    member = AccountUser.create!(account: other, user: @user, role: 'administrator')
    company = JrcServiceDesk::OperatorCompany.create!(account: other, name: 'Other', code: SecureRandom.hex(4), active: true)
    unit = JrcServiceDesk::Unit.create!(account: other, operator_company: company, name: 'Other', code: 'other', active: true)
    JrcServiceDesk::GlpiConnection.create!(account: other, base_url: 'https://other.example.invalid/apirest.php',
      user_token: 'other-synthetic', app_token: 'other-synthetic', enabled: true, timezone: 'UTC',
      entity_mappings: [{ entity_id: 7, unit_id: unit.id }], user_mappings: [])
    foreign = Object.new
    def foreign.get(*)
      { 'id' => 101, 'entities_id' => 0 }
    end
    def foreign.collection(*)
      [{ 'id' => 1, 'items_id' => 101, 'itemtype' => 'Ticket', 'content' => 'Foreign' }]
    end
    assert_raises(Pundit::NotAuthorizedError) do
      query.related(access: JrcServiceDesk::Glpi::Access.new(account: other, user: @user, account_user: member),
        client: foreign, kind: 'followups', ticket_id: 101)
    end
  end

  def test_agent_actor_scope_is_paged_and_private_followups_remain_hidden
    @member.update!(role: 'agent')
    JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
    @connection.update!(user_mappings: [{ account_user_id: @member.id, glpi_user_id: 77 }])
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    actors = (1..1000).map { |id| { 'id' => id, 'users_id' => id + 100, 'type' => 1, 'tickets_id' => 101 } }
    actors << { 'id' => 1001, 'users_id' => 77, 'type' => 1, 'tickets_id' => 101 }
    client.expect(:collection, actors, ['Ticket/101/Ticket_User/'])
    client.expect(:collection,
      [{ 'id' => 1, 'items_id' => 101, 'itemtype' => 'Ticket', 'content' => 'Private', 'is_private' => 1 },
       { 'id' => 2, 'items_id' => 101, 'itemtype' => 'Ticket', 'content' => 'Public', 'is_private' => 0 }], ['Ticket/101/ITILFollowup/'])
    result = JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
      client: client, kind: 'followups', ticket_id: 101)
    assert_equal [2], result.fetch(:items).map { |row| row.fetch('id') }
  end

  def test_linked_problem_must_also_belong_to_an_authorized_entity
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    client.expect(:collection, [{ 'id' => 1, 'tickets_id' => 101, 'problems_id' => 201 }], ['Ticket/101/Problem_Ticket/'])
    client.expect(:get, { 'id' => 201, 'entities_id' => 999 }, ['Problem/201'])
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
        client: client, kind: 'problem_links', ticket_id: 101)
    end
  end

  def test_linked_asset_must_also_belong_to_an_authorized_entity
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    client.expect(:collection, [{ 'id' => 1, 'tickets_id' => 101, 'items_id' => 201, 'itemtype' => 'Computer' }], ['Ticket/101/Item_Ticket/'])
    client.expect(:get, { 'id' => 201, 'entities_id' => 999 }, ['Computer/201'])
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
        client: client, kind: 'assets', ticket_id: 101)
    end
  end

  def test_template_fields_are_scoped_to_the_authorized_template
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 301, 'entities_id' => 0 }, ['TicketTemplate/301'])
    client.expect(:collection, [{ 'id' => 1, 'tickettemplates_id' => 301, 'num' => 1 }], ['TicketTemplate/301/TicketTemplateMandatoryField/'])
    result = JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
      client: client, kind: 'template_mandatory', ticket_id: 301, parent_type: 'TicketTemplate')
    assert_equal [1], result.fetch(:items).map { |row| row['num'] }
  end

  def test_problem_groups_use_the_real_glpi_group_problem_type
    client = Minitest::Mock.new
    client.expect(:get, { 'id' => 201, 'entities_id' => 0 }, ['Problem/201'])
    client.expect(:collection, [{ 'id' => 1, 'problems_id' => 201, 'groups_id' => 9 }], ['Problem/201/Group_Problem/'])
    result = JrcServiceDesk::Glpi::ResourceQuery.new.related(access: JrcServiceDesk::Glpi::Access.new(@identity),
      client: client, kind: 'actor_groups', ticket_id: 201, parent_type: 'Problem')
    assert_equal [9], result.fetch(:items).map { |row| row['groups_id'] }
  end
end
