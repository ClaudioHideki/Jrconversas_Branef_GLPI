# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
module JrcServiceDesk
  module Glpi; end
end
require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/glpi/ticket_actors'

class GlpiTicketActorsTest < Minitest::Test
  def test_actor_roles_are_distinct_and_all_pages_are_consumed
    client = Minitest::Mock.new
    rows = (1..205).map { |id| { 'id' => id, 'tickets_id' => 101, 'users_id' => id, 'type' => 1 } }
    rows << { 'id' => 206, 'tickets_id' => 101, 'users_id' => 900, 'type' => 2 }
    rows << { 'id' => 207, 'tickets_id' => 101, 'users_id' => 901, 'type' => 3 }
    client.expect(:collection, rows.each, ['Ticket/101/Ticket_User/'])
    result = JrcServiceDesk::Glpi::TicketActors.new.call(client: client, ticket_id: 101)
    assert result.fetch('actor_scope_available')
    assert_equal [900], result.fetch('assigned_user_ids')
    assert_equal (1..205).to_a, result.fetch('requester_user_ids')
    refute_includes result.fetch('actor_user_ids'), 901
  end

  def test_denied_actors_are_unavailable_rather_than_unassigned
    client = Object.new
    def client.collection(*)
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403)
    end
    result = JrcServiceDesk::Glpi::TicketActors.new.call(client: client, ticket_id: 101)
    refute result.fetch('actor_scope_available')
    assert_nil result.fetch('assigned_user_ids')
    assert_equal 'ERROR_RIGHT_MISSING', result.fetch('actor_scope_error')
  end

  def test_wrong_parent_never_contributes_an_actor_grant
    client = Minitest::Mock.new
    client.expect(:collection, [{ 'id' => 1, 'tickets_id' => 999, 'users_id' => 900, 'type' => 2 }], ['Ticket/101/Ticket_User/'])
    result = JrcServiceDesk::Glpi::TicketActors.new.call(client: client, ticket_id: 101)
    refute result.fetch('actor_scope_available')
    assert_nil result.fetch('actor_user_ids')
  end
end
