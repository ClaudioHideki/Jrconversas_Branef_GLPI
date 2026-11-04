# frozen_string_literal: true

require_relative 'glpi_test_helper'

# Synthetic GLPI state, behind the real command service; never connects to a server.
class GlpiCommandSource
  attr_accessor :failure, :on_profile, :ignore_write, :denied
  attr_reader :writes, :rows

  def initialize
    @writes = []
    @rows = { 'Ticket/101' => { 'id' => 101, 'entities_id' => 0, 'date_mod' => 'v1', 'type' => 1 },
      'Problem/201' => { 'id' => 201, 'entities_id' => 0, 'date_mod' => 'v1' },
      'Change/301' => { 'id' => 301, 'entities_id' => 0, 'date_mod' => 'v1' } }
  end

  def session
    yield self
  end

  def get(path, *)
    if path == 'getActiveProfile/'
      on_profile&.call
      return { 'active_profile' => %w[ticket followup task ticketvalidation changevalidation problem change knowbase itilcategory tickettemplate].to_h { |key| [key, denied ? 0 : 1048575] } }
    end
    return { 'session' => { 'glpiID' => 900 } } if path == 'getFullSession/'
    row = rows[path]
    raise JrcServiceDesk::Glpi::Error.new('ERROR_ITEM_NOT_FOUND', 404) unless row

    row.deep_dup
  end

  def collection(path, *)
    return [{ 'id' => 1, 'knowbaseitems_id' => 501, 'entities_id' => 0 }] if path == 'KnowbaseItem/501/Entity_KnowbaseItem/'
    return [{ 'id' => 1, 'users_id' => 77, 'entities_id' => 0 }] if path == 'User/77/Profile_User/'
    if path.match?(%r{\A(?:Ticket|Problem|Change)/\d+/(?:Ticket_User|Group_Ticket|Problem_User|Problem_Group|Change_User|Change_Group)/\z})
      type, id, relation = path.split('/')
      row = rows["#{type}/#{id}"] || {}
      key = relation.include?('Group') ? 'groups_id' : 'users_id'
      value = row[key == 'groups_id' ? '_groups_id_assign' : '_users_id_assign']
      return value ? [{ 'id' => 1, "#{type.downcase}s_id" => id.to_i, key => value, 'type' => 2 }] : []
    end

    []
  end

  def create_item(type, input)
    write!(:post, type, nil, input)
  end

  def update_item(type, id, input)
    write!(:patch, type, id, input)
  end

  def delete_item(type, id, **)
    write!(:delete, type, id, {})
  end

  def write!(verb, type, id, input)
    raise 'Intent was not durable before sending' unless JrcServiceDesk::GlpiCommand.where(state: 'sending').exists?

    writes << [verb, type, id, input.deep_dup]
    id ||= 501
    unless ignore_write
      if verb == :delete
        rows.delete("#{type}/#{id}")
      else
        rows["#{type}/#{id}"] = (rows["#{type}/#{id}"] || {}).merge(input).merge('id' => id, 'date_mod' => 'v2')
      end
    end
    raise JrcServiceDesk::Glpi::Error.new(failure, failure == 'ERROR_RIGHT_MISSING' ? 403 : 502) if failure

    { 'id' => id, 'deleted' => verb == :delete }
  end
end

class GlpiCommandsTest < GlpiIntegrationTest
  def setup
    super
    @remote = GlpiCommandSource.new
    @execute = JrcServiceDesk::Glpi::Execute.new(client_factory: ->(_) { @remote })
  end

  def execute(operation = 'ticket.update', target: 101, attributes: { 'name' => 'Changed' }, key: SecureRandom.uuid, **options)
    @execute.call(access: JrcServiceDesk::Glpi::Access.new(@identity), operation: operation, target_id: target,
      entity_id: 0, attributes: attributes, idempotency_key: key, **options)
  end

  def test_all_ticket_transitions_and_assignment_are_confirmed_by_readback
    { 'update' => { 'name' => 'Updated' }, 'assign' => { '_users_id_assign' => 77 }, 'transfer' => { 'entities_id' => 0 },
      'priority' => { 'priority' => 5 }, 'pause' => {}, 'resume' => {}, 'close' => {}, 'reopen' => {},
      'solve' => { 'parent_id' => 101, 'content' => 'Solution' } }.each do |verb, input|
      @remote.rows['User/77'] = { 'id' => 77, 'entities_id' => 0 }
      receipt = execute("ticket.#{verb}", target: verb == 'solve' ? nil : 101, attributes: input)
      assert_equal 'succeeded', receipt.fetch(:state), "#{verb}: #{receipt}"
      assert_equal 900, receipt.fetch(:technical_user_id)
    end
    record = JrcServiceDesk::GlpiCommand.last
    assert_equal @member.id, record.account_user_id
    refute_includes record.receipt.to_json, 'synthetic-user'
  end

  def test_followup_task_and_validation_crud_keeps_exact_parent_and_private_fields
    %w[followup task].each do |family|
      receipt = execute("#{family}.create", target: nil, attributes: { 'parent_id' => 101, 'content' => 'Private', 'is_private' => 1 })
      assert_equal 'succeeded', receipt[:state]
      assert_equal 'succeeded', execute("#{family}.update", target: 501, attributes: { 'parent_id' => 101, 'content' => 'Edited' })[:state]
      assert_equal 'succeeded', execute("#{family}.delete", target: 501, attributes: { 'parent_id' => 101 })[:state]
    end
    @remote.rows['User/77'] = { 'id' => 77, 'entities_id' => 0 }
    request = execute('validation.request', target: nil, attributes: { 'parent_id' => 101, 'users_id_validate' => 77, 'comment_submission' => 'Approve' })
    assert_equal 'succeeded', request[:state]
    @remote.denied = true
    assert_equal 'rejected', execute('validation.decide', target: 501,
      attributes: { 'parent_id' => 101, 'status' => 3, 'comment_validation' => 'Decision' })[:state]
    refute @remote.writes.any? { |row| row[3].key?('users_id_validate') && row[0] == :patch }
  end

  def test_problem_change_and_knowledge_crud
    %w[problem change knowledge].each do |family|
      fields = family == 'knowledge' ? { 'name' => 'Article', 'answer' => 'Answer' } : { 'name' => 'Synthetic', 'content' => 'Description' }
      assert_equal 'succeeded', execute("#{family}.create", target: nil, attributes: fields)[:state]
      assert_equal 'succeeded', execute("#{family}.update", target: 501, attributes: { 'name' => 'Edited' })[:state]
      assert_equal 'succeeded', execute("#{family}.delete", target: 501, attributes: {}, reason: 'Synthetic test')[:state]
    end
  end

  def test_same_key_returns_receipt_and_changed_payload_conflicts_without_resending
    one = execute(key: 'same')
    assert_equal one[:id], execute(key: 'same')[:id]
    assert_equal 1, @remote.writes.size
    assert_raises(JrcServiceDesk::IdempotencyConflict) { execute(key: 'same', attributes: { 'name' => 'Other' }) }
    assert_raises(JrcServiceDesk::IdempotencyConflict) { execute('ticket.close', key: 'same', attributes: {}) }
  end

  def test_timeout_after_post_stays_indeterminate_and_reconcile_never_reposts
    @remote.failure = 'source_unavailable'
    receipt = execute('followup.create', target: nil, attributes: { 'parent_id' => 101, 'content' => 'Hello' }, key: 'timeout')
    assert_equal 'indeterminate', receipt[:state]
    assert_equal receipt[:id], execute('followup.create', target: nil, attributes: { 'parent_id' => 101, 'content' => 'Hello' }, key: 'timeout')[:id]
    @remote.failure = nil
    reconciled = JrcServiceDesk::Glpi::Reconcile.new(client_factory: ->(_) { @remote }).call(
      access: JrcServiceDesk::Glpi::Access.new(@identity), command: JrcServiceDesk::GlpiCommand.find(receipt[:id]), remote_id: 501)
    assert_equal 'succeeded', reconciled[:state]
    assert_equal 1, @remote.writes.size
  end

  def test_configuration_change_and_revocation_before_sending_prevent_write
    @remote.on_profile = -> { @connection.update!(timezone: 'Europe/London') }
    receipt = execute
    assert_equal 'rejected', receipt[:state]
    assert_equal 'configuration_changed', receipt[:error_code]
    assert_empty @remote.writes
    @remote.on_profile = -> { @member.update!(role: 'agent') }
    assert_equal 'rejected', execute[:state]
    assert_empty @remote.writes
  end

  def test_entity_parent_and_expected_version_checks_prevent_write
    @remote.rows['Ticket/101']['entities_id'] = 999
    assert_equal 'rejected', execute[:state]
    @remote.rows['Ticket/101']['entities_id'] = 0
    assert_equal 'rejected', execute(expected_version: 'old')[:state]
    @remote.rows['TicketTask/501'] = { 'id' => 501, 'tickets_id' => 999 }
    assert_equal 'rejected', execute('task.update', target: 501, attributes: { 'parent_id' => 101, 'content' => 'No' })[:state]
    assert_empty @remote.writes
  end

  def test_unconfirmed_write_and_foreign_link_are_never_success
    @remote.ignore_write = true
    assert_equal 'indeterminate', execute[:state]
    # A separate fully authorized ticket avoids reusing an unresolved object.
    @remote.rows['Ticket/102'] = { 'id' => 102, 'entities_id' => 0 }
    @remote.ignore_write = false
    @remote.rows['Problem/999'] = { 'id' => 999, 'entities_id' => 999 }
    receipt = execute('problem_link.create', target: nil, attributes: { 'parent_id' => 102, 'problems_id' => 999 })
    assert_equal 'rejected', receipt[:state]
    assert_equal 1, @remote.writes.size
  end

  def test_problem_change_operational_verbs_and_linked_targets
    %w[problem change].each do |family|
      id = family == 'problem' ? 201 : 301
      { 'assign' => { '_users_id_assign' => 77 }, 'priority' => { 'priority' => 5 },
        'pause' => {}, 'resume' => {}, 'close' => {}, 'reopen' => {},
        'solve' => { 'parent_id' => id, 'content' => 'Solved' } }.each do |verb, input|
        @remote.rows['User/77'] = { 'id' => 77 }
        assert_equal 'succeeded', execute("#{family}.#{verb}", target: verb == 'solve' ? nil : id, attributes: input)[:state]
      end
    end
    { 'problem_link' => ['problems_id', 201], 'change_link' => ['changes_id', 301],
      'knowledge_link' => ['knowbaseitems_id', 501], 'actor' => ['users_id', 77],
      'group' => ['groups_id', 701], 'supplier' => ['suppliers_id', 801] }.each do |family, values|
      field, id = values
      @remote.rows['KnowbaseItem/501'] = { 'id' => 501, 'name' => 'Article' }
      @remote.rows['Group/701'] = { 'id' => 701, 'entities_id' => 0 }
      @remote.rows['Supplier/801'] = { 'id' => 801, 'entities_id' => 0 }
      attributes = { 'parent_id' => 101, field => id }
      attributes['type'] = 2 if %w[actor group supplier].include?(family)
      assert_equal 'succeeded', execute("#{family}.create", target: nil, attributes: attributes)[:state], family
      assert_equal 'succeeded', execute("#{family}.delete", target: 501, attributes: { 'parent_id' => 101 })[:state], family
    end
  end

  def test_input_rejects_authorship_overrides_unknown_fields_and_missing_parent
    assert_raises(ArgumentError) { execute(attributes: { 'users_id' => 77 }) }
    assert_raises(ArgumentError) { execute('task.create', target: nil, attributes: { 'content' => 'No parent' }) }
    assert_raises(ArgumentError) { execute('validation.decide', target: 501, attributes: { 'parent_id' => 101, 'status' => 9 }) }
    assert_empty @remote.writes
  end
end
