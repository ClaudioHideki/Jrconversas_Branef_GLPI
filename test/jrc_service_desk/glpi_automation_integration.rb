# frozen_string_literal: true

require_relative 'glpi_test_helper'
require_relative 'glpi_source_fixture'

class GlpiAutomationTest < GlpiIntegrationTest
  def setup
    super
    @connection.update!(primary_source: true)
    @account.update!(custom_attributes: @account.custom_attributes.merge('nico_enabled' => true))
    @unit_member = JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
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
    @unit_member.update!(active: false)
    assert_raises(Pundit::NotAuthorizedError) do
      service.call(user_context: @identity, reference: @reference, operation: 'ticket.close', attributes: {}, idempotency_key: 'revoked')
    end
    assert_empty @remote.writes
  end

  def test_conversation_and_case_links_store_typed_remote_identity_without_a_native_ticket
    channel = Channel::Api.create!(account: @account)
    inbox = Inbox.create!(account: @account, channel: channel, name: 'Synthetic GLPI conversation')
    contact = Contact.create!(account: @account, name: 'Synthetic requester')
    contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
    conversation = Conversation.create!(account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    incident = JrcServiceDesk::Incident.create!(account: @account, unit: @unit, created_by_membership: @unit_member,
      title: 'Native historical case', severity: 'normal', status: 'open', resource_kind: 'incident', started_at: Time.current,
      idempotency_key: SecureRandom.uuid, request_fingerprint: 'a' * 64)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      service = JrcServiceDesk::Glpi::LinkLocalReference.new
      one = service.call(user_context: @identity, reference: @reference, conversation_id: conversation.id)
      assert_equal one.id, service.call(user_context: @identity, reference: @reference, conversation_id: conversation.id).id
      case_link = service.call(user_context: @identity, reference: @reference, incident_id: incident.id)
      assert_equal 'Ticket', one.glpi_reference.itemtype
      assert_equal 101, one.glpi_reference.remote_id
      assert_equal incident.id, case_link.incident_id
      assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
      access = JrcNico::OperationalAccess.new(account: @account, user: @user).authorize!
      read = JrcNico::ToolExecutor.new(access).call('read_conversation', 'conversation_id' => conversation.display_id)
      assert_equal @reference, read.fetch(:glpi_references).fetch(:items).first.fetch(:reference)
      http = ActionDispatch::Integration::Session.new(Rails.application)
      http.get("/api/v1/accounts/#{@account.id}/conversations/#{conversation.display_id}", headers: @user.create_new_auth_token)
      assert_equal 200, http.response.status
      assert_equal 101, JSON.parse(http.response.body).dig('glpi_references', 'items', 0, 'reference', 'remote_id')
      @unit_member.update!(active: false)
      assert_raises(Pundit::NotAuthorizedError) do
        service.call(user_context: @identity, reference: @reference, conversation_id: conversation.id)
      end
    end
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
      @remote.failure = 'source_unavailable'
      uncertain = operator.ask(message: 'Synthetic ambiguous write', request_id: SecureRandom.uuid,
        prepared: { 'tool' => 'execute_glpi_operation', 'arguments' => { 'reference' => @reference,
          'operation' => 'ticket.update', 'attributes' => { 'name' => 'Uncertain' }, 'expected_version' => 'v2' } })
      operator.execute(uncertain)
      assert_equal 'unknown', uncertain.reload.status
      assert_equal 'indeterminate', uncertain.result.dig('command', 'state')
      operator.execute(uncertain)
      assert_equal 2, @remote.writes.size
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

  def test_real_nico_read_result_retains_typed_provenance_and_is_rechecked_after_disable
    access = JrcNico::OperationalAccess.new(account: @account, user: @user).authorize!
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      result = JrcNico::ToolExecutor.new(access).call('read_glpi_reference', 'reference' => @reference)
      type, id = result.fetch(:resources).first
      assert_equal 'JrcServiceDesk::GlpiReference', type
      record = JrcNico::DomainAccess.authorize_resource!(access, type, id)
      assert_equal @reference, record.reference
      @connection.update!(enabled: false)
      assert_raises(JrcServiceDesk::Glpi::Error) { JrcNico::DomainAccess.authorize_resource!(access, type, id) }
    end
  end

  def test_native_nico_facts_and_direct_ticket_tool_cannot_be_used_as_glpi_fallback
    context = JrcNico::Helpdesk::Context.new(@member)
    assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcNico::Helpdesk::Facts.new(context: context, policy: nil, ticket: nil, trigger: 'monitor').call
    end
    assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcNico::DomainActions.new(context.access).call('read_service_ticket', 'ticket_id' => 101)
    end
    group = JrcNico::Helpdesk::Catalog.call(account: @account).find { |row| row[:key] == 'D1' }
    assert_equal 'glpi_typed_command_required', group[:status]
    refute group[:automatic_execution]
  end

  def test_nico_context_and_explicit_bounded_search_expose_usable_typed_references_without_bulk_content
    access = JrcNico::OperationalAccess.new(account: @account, user: @user).authorize!
    context = JrcNico::DomainActions.new(access).call('service_desk_context', {})
    assert_equal @connection.id, context.dig(:glpi, :connection_id)
    assert_equal [0], context.dig(:glpi, :entity_ids)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      result = JrcNico::ToolExecutor.new(access).call('search_glpi_tickets', 'entity_id' => 0, 'search' => 'Synthetic')
      assert_equal @reference, result.fetch(:items).first.fetch(:reference)
      refute result.fetch(:items).first.key?(:content)
      assert_equal 20, result.fetch(:meta).fetch(:per_page)
    end
  end

  def test_nico_ticket_creation_uses_a_bound_destination_and_human_confirmation_without_native_copy
    destination = { 'connection_id' => @connection.id, 'connection_version' => @connection.lock_version, 'entity_id' => 0 }
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      operator = JrcNico::OperatorSession.new(account: @account, user: @user)
      command = operator.ask(message: 'Create synthetic GLPI ticket', request_id: SecureRandom.uuid,
        prepared: { 'tool' => 'create_glpi_ticket', 'arguments' => { 'destination' => destination,
          'attributes' => { 'name' => 'Synthetic remote', 'content' => 'Description', 'type' => 1, 'urgency' => 3, 'impact' => 3 } } })
      assert_equal 'awaiting_confirmation', command.status
      assert_empty @remote.writes
      operator.execute(command)
      assert_equal 'succeeded', command.reload.status
      assert_equal 'ticket.create', command.result.dig('command', 'operation')
      assert_equal '501', command.result.dig('command', 'remote_id')
      assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
      operator.execute(command)
      assert_equal 1, @remote.writes.size
    end
  end

  def test_creation_destination_version_change_is_rejected_before_network
    destination = { 'connection_id' => @connection.id, 'connection_version' => @connection.lock_version, 'entity_id' => 0 }
    @connection.update!(timezone: 'Europe/London')
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::AutomationCommand.new.create(user_context: @identity, destination: destination,
        attributes: { 'name' => 'No write', 'content' => 'Description', 'type' => 1, 'urgency' => 3, 'impact' => 3 }, idempotency_key: 'stale-destination')
    end
    assert_equal 'configuration_changed', error.code
    assert_empty @remote.writes
  end
end
