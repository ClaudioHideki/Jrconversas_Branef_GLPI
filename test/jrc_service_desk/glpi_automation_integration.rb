# frozen_string_literal: true

require_relative 'glpi_test_helper'
require_relative 'glpi_source_fixture'

class GlpiAutomationTest < GlpiIntegrationTest
  def setup
    super
    @connection.update!(primary_source: true)
    @account.update!(custom_attributes: @account.custom_attributes.merge('nico_enabled' => true))
    @remote = GlpiCommandSource.new
    @reference = { 'account_id' => @account.id, 'connection_id' => @connection.id,
      'itemtype' => 'Ticket', 'remote_id' => 101, 'entity_id' => 0 }
  end

  def test_reference_requires_the_full_account_connection_type_and_remote_identity
    reference = JrcServiceDesk::Glpi::Reference.new(@reference)
    row = reference.authorize!(access: JrcServiceDesk::Glpi::Access.new(@identity), client: @remote)
    assert_equal 101, row['id']
    refute_equal '101', reference.identity_key
    assert_raises(ArgumentError) { JrcServiceDesk::Glpi::Reference.new('ticket_id' => 101) }
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::Reference.new(@reference.merge('connection_id' => @connection.id + 1)).authorize!(
        access: JrcServiceDesk::Glpi::Access.new(@identity), client: @remote)
    end
    assert_raises(Pundit::NotAuthorizedError) do
      JrcServiceDesk::Glpi::Reference.new(@reference.merge('entity_id' => 999)).authorize!(
        access: JrcServiceDesk::Glpi::Access.new(@identity), client: @remote)
    end
  end

  def test_automation_uses_the_durable_executor_and_never_duplicates_a_key
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      service = JrcServiceDesk::Glpi::AutomationCommand.new
      options = { user_context: @identity, reference: @reference, operation: 'ticket.update', attributes: { 'name' => 'Automatic' },
        idempotency_key: 'automatic-key', expected_version: 'v1' }
      first = service.call(**options)
      assert_equal 'succeeded', first[:state]
      assert_equal first[:id], service.call(**options)[:id]
      assert_equal 1, @remote.writes.size
      assert_equal 900, first[:technical_user_id]
      assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
    end
  end

  def test_automation_rechecks_account_unit_and_connection_every_execution
    service = JrcServiceDesk::Glpi::AutomationCommand.new
    @connection.update!(enabled: false)
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      service.call(user_context: @identity, reference: @reference, operation: 'ticket.close', attributes: {}, idempotency_key: 'disabled')
    end
    assert_equal 'not_configured', error.code
    @connection.update!(enabled: true)
    @member.update!(role: 'agent')
    assert_raises(Pundit::NotAuthorizedError) do
      service.call(user_context: @identity, reference: @reference, operation: 'ticket.close', attributes: {}, idempotency_key: 'revoked')
    end
    assert_empty @remote.writes
  end

  def test_native_mutation_guards_refuse_selected_glpi_even_when_disabled_but_keep_native_history_readable
    [true, false].each do |enabled|
      @connection.update!(enabled: enabled)
      assert_raises(JrcServiceDesk::Glpi::Error) do
        JrcServiceDesk::CreateTicketService.new(user_context: @identity).call(unit_id: @unit.id, attributes: {}, idempotency_key: "native-#{enabled}")
      end
      http = ActionDispatch::Integration::Session.new(Rails.application)
      http.post("/api/v1/accounts/#{@account.id}/jrc_service_desk/tickets", headers: @user.create_new_auth_token, params: {}, as: :json)
      assert_equal 409, http.response.status
      assert_equal 'glpi_source_required', JSON.parse(http.response.body)['code']
    end
    assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
    @connection.update!(primary_source: false)
    assert JrcServiceDesk::NativeSourceGuard.call(@identity)
  end

  def test_real_nico_catalogue_has_typed_remote_tools_and_hides_native_collision_paths
    access = JrcNico::OperationalAccess.new(account: @account, user: @user).authorize!
    names = JrcNico::ToolCatalog.new(access).available.map { |tool| tool[:name] }
    assert_includes names, 'execute_glpi_operation'
    assert_includes names, 'read_glpi_reference'
    refute_includes names, 'update_service_ticket'
    refute_includes names, 'create_service_ticket_task'
    refute JrcNico::ExecutionPolicy.automatic?(Struct.new(:message, :source_notice_id).new('Execute a operação GLPI', nil), 'execute_glpi_operation')
    @connection.update!(primary_source: false)
    native_names = JrcNico::ToolCatalog.new(access).available.map { |tool| tool[:name] }
    assert_includes native_names, 'update_service_ticket'
    refute_includes native_names, 'execute_glpi_operation'
  end

  def test_actual_nico_confirmation_commits_intent_before_remote_io_and_preserves_unknown_results
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      operator = JrcNico::OperatorSession.new(account: @account, user: @user)
      command = operator.ask(message: 'Synthetic GLPI edit', request_id: SecureRandom.uuid,
        prepared: { 'tool' => 'execute_glpi_operation', 'arguments' => { 'reference' => @reference,
          'operation' => 'ticket.update', 'attributes' => { 'name' => 'From NICO' }, 'expected_version' => 'v1' } })
      assert_equal 'awaiting_confirmation', command.status
      assert_empty @remote.writes
      operator.execute(command)
      assert_equal 'succeeded', command.reload.status
      assert_equal 1, @remote.writes.size
      assert JrcServiceDesk::GlpiCommand.where(account: @account, account_user: @member, state: 'succeeded').exists?
      operator.execute(command)
      assert_equal 1, @remote.writes.size
    end
  end

  def test_nico_cannot_execute_a_remote_tool_without_approved_human_command
    access = JrcNico::OperationalAccess.new(account: @account, user: @user).authorize!
    assert_raises(Pundit::NotAuthorizedError) do
      JrcNico::HelpdeskToolActions.new(access).call('execute_glpi_operation',
        'reference' => @reference, 'operation' => 'ticket.close', 'attributes' => {})
    end
    assert_empty @remote.writes
  end
end
