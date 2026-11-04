# frozen_string_literal: true

require_relative 'glpi_test_helper'

class GlpiProjectionTest < GlpiIntegrationTest
  def test_native_default_and_account_selected_source
    assert_equal 'native', JrcServiceDesk::Glpi::PrimarySource.for(@identity)
    @connection.update!(primary_source: true)
    assert_equal 'glpi', JrcServiceDesk::Glpi::PrimarySource.for(@identity)
    @connection.update!(enabled: false)
    assert_equal 'glpi', JrcServiceDesk::Glpi::PrimarySource.for(@identity)
  end

  def test_root_without_label_is_indexed_by_verified_entity_id
    client = Minitest::Mock.new
    client.expect(:collection, [{ '2' => 101, '1' => 'Root ticket' }], ['search/Ticket/', Hash])
    client.expect(:get, { 'id' => 101, 'entities_id' => 0, 'name' => 'Root ticket' }, ['Ticket/101'])
    run = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: client)
    assert_equal 'complete', run.state
    row = JrcServiceDesk::GlpiTicketSnapshot.find_by!(glpi_connection: @connection, remote_id: 101)
    assert_equal 0, row.entity_id
    assert_equal @unit.id, row.unit_id
    assert_equal @connection.lock_version, row.connection_version
    client.verify
  end

  def test_detail_mismatch_is_partial_and_never_invents_a_unit
    client = Minitest::Mock.new
    client.expect(:collection, [{ '2' => 101 }], ['search/Ticket/', Hash])
    client.expect(:get, { 'id' => 101, 'entities_id' => 999 }, ['Ticket/101'])
    run = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: client)
    assert_equal 'partial', run.state
    assert_equal 0, JrcServiceDesk::GlpiTicketSnapshot.where(glpi_connection: @connection).count
    assert_equal 'entity_mismatch', run.coverage.fetch('0').fetch('error')
  end

  def test_config_change_invalidates_old_projection
    row = JrcServiceDesk::GlpiTicketSnapshot.create!(account: @account, glpi_connection: @connection, unit: @unit,
      remote_id: 101, entity_id: 0, connection_version: @connection.lock_version, payload: { 'title' => 'Old' }, observed_at: Time.current)
    assert_includes JrcServiceDesk::GlpiTicketSnapshot.current_for(@connection), row
    @connection.update!(categories: [{ id: 1, name: 'New', entity_id: 0 }])
    assert_empty JrcServiceDesk::GlpiTicketSnapshot.current_for(@connection)
  end

  def test_cross_account_projection_is_invalid
    other = Account.create!(name: 'Other projection', status: 'active')
    row = JrcServiceDesk::GlpiTicketSnapshot.new(account: other, glpi_connection: @connection, unit: @unit,
      remote_id: 101, entity_id: 0, connection_version: 0, payload: {}, observed_at: Time.current)
    refute row.valid?
    assert row.errors[:glpi_connection].any?
  end

  def test_duplicate_ticket_prevents_complete_coverage
    client = Minitest::Mock.new
    client.expect(:collection, [{ '2' => 101 }, { '2' => 101 }], ['search/Ticket/', Hash])
    client.expect(:get, { 'id' => 101, 'entities_id' => 0 }, ['Ticket/101'])
    run = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: client)
    assert_equal 'partial', run.state
    assert_equal 'source_changed', run.coverage.fetch('0').fetch('error')
  end

  def test_remote_denial_is_not_an_empty_success
    client = Object.new
    def client.collection(*)
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403)
    end
    run = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: client)
    assert_equal 'partial', run.state
    assert_equal 'ERROR_RIGHT_MISSING', run.coverage.fetch('0').fetch('error')
  end
end
