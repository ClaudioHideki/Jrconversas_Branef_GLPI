# frozen_string_literal: true

require_relative 'glpi_test_helper'
require_relative 'glpi_source_fixture'

class GlpiNicoTemplateSource < GlpiCommandSource
  attr_accessor :on_template_read
  attr_reader :rules, :policy_reads

  def initialize
    super
    @policy_reads = 0
    @rules = { 'Mandatory' => [], 'Hidden' => [], 'Predefined' => [
      { 'id' => 1, 'tickettemplates_id' => 10, 'num' => 10, 'value' => '5' }
    ] }
    rows['TicketTemplate/10'] = { 'id' => 10, 'name' => 'Synthetic template', 'entities_id' => 0, 'is_recursive' => 0, 'date_mod' => 'v1' }
  end

  def get(path, *)
    if path == 'getActiveProfile/'
      response = super
      return response.merge('active_profile' => response.fetch('active_profile').merge('tickettemplates_id' => 10))
    end
    if path == 'TicketTemplate/10'
      @policy_reads += 1
      on_template_read&.call
    end
    super
  end

  def collection(path, *)
    match = path.match(%r{\ATicketTemplate/10/TicketTemplate(Mandatory|Hidden|Predefined)Field/\z})
    return rules.fetch(match[1]).deep_dup if match

    super
  end
end

class GlpiNicoTemplateTest < GlpiIntegrationTest
  def setup
    super
    @connection.update!(primary_source: true)
    @account.update!(custom_attributes: @account.custom_attributes.merge('nico_enabled' => true))
    JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
    @remote = GlpiNicoTemplateSource.new
    @operator = JrcNico::OperatorSession.new(account: @account, user: @user)
  end

  def prepare(attributes = {})
    @operator.ask(message: 'Create synthetic policy-bound ticket', request_id: SecureRandom.uuid,
      prepared: { 'tool' => 'create_glpi_ticket', 'arguments' => {
        'destination' => { 'connection_id' => @connection.id, 'connection_version' => @connection.lock_version, 'entity_id' => 0 },
        'attributes' => { 'name' => 'Synthetic policy ticket', 'content' => 'Actual operator description' }.merge(attributes) } })
  end

  def test_prepare_reads_current_policy_outside_transactions_and_stamps_trusted_original_selection
    @remote.on_template_read = -> { refute ActiveRecord::Base.connection.transaction_open?, 'NICO prepare source I/O held a DB transaction' }
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      command = prepare
      assert_operator @remote.policy_reads, :>, 0
      assert_equal 'awaiting_confirmation', command.status
      form = JrcServiceDesk::Glpi::TicketForm.new.call(access: JrcServiceDesk::Glpi::Access.new(@identity), client: @remote,
        filters: { 'entity_id' => 0, 'type' => 1 })
      assert_equal form[:version], command.execution_context['glpi_template_version']
      assert_equal({ 'entity_id' => 0, 'type' => 1, 'category_id' => 0, 'template_id' => nil },
        command.execution_context['glpi_template_selection'])
      refute command.arguments.fetch('attributes').key?('urgency')
      refute command.arguments.fetch('attributes').key?('template_id')
      assert_empty @remote.writes
      assert_equal 0, JrcServiceDesk::GlpiCommand.where(account: @account).count
    end
  end

  def test_model_change_between_prepare_and_confirm_prevents_all_business_writes
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      command = prepare
      @remote.rows['TicketTemplate/10']['date_mod'] = 'v2'
      @remote.rules['Predefined'].first['value'] = '4'
      @operator.execute(command)
      assert_equal 'failed', command.reload.status
      assert_equal 'template_changed', command.result.dig('command', 'error_code')
      assert_empty @remote.writes
      assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
    end
  end

  def test_current_policy_defaults_and_readback_use_manual_approval_without_duplicate_confirmation
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
      command = prepare('template_id' => 10)
      assert_equal 10, command.execution_context.dig('glpi_template_selection', 'template_id')
      assert_empty @remote.writes
      @operator.execute(command)
      assert_equal 'succeeded', command.reload.status
      assert_equal 5, @remote.rows.fetch('Ticket/501')['urgency']
      assert_equal 10, @remote.rows.fetch('Ticket/501')['_tickettemplate']
      assert_equal command.execution_context['glpi_template_version'], JrcServiceDesk::GlpiCommand.find(command.result.dig('command', 'id')).template_version
      @operator.execute(command)
      assert_equal 1, @remote.writes.size
    end
  end

  def test_connection_change_after_prepare_source_proof_cannot_store_an_approved_preview
    form = JrcServiceDesk::Glpi::TicketForm.new
    read = form.method(:call)
    after_proof = lambda do |**arguments|
      policy = read.call(**arguments)
      @account.with_lock { @connection.update!(timezone: 'Europe/London') }
      policy
    end
    form.stub(:call, after_proof) do
      JrcServiceDesk::Glpi::TicketForm.stub(:new, -> { form }) do
        JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { @remote }) do
          error = assert_raises(JrcServiceDesk::Glpi::Error) { prepare }
          assert_equal 'configuration_changed', error.code
          refute @operator.session.commands.where(status: 'awaiting_confirmation').exists?
          assert_empty @remote.writes
        end
      end
    end
  end

  def test_other_native_account_keeps_native_tools_without_template_source_reads
    @connection.update!(primary_source: false)
    access = JrcNico::OperationalAccess.new(account: @account, user: @user).authorize!
    JrcServiceDesk::Glpi::Client.stub(:new, ->(_) { flunk 'Native account must not read GLPI template policy' }) do
      tools = JrcNico::ToolCatalog.new(access).available.map { |tool| tool[:name] }
      assert_includes tools, 'create_service_ticket'
      refute_includes tools, 'create_glpi_ticket'
      assert JrcNico::ToolCatalog.new(access).validate!('create_service_ticket', 'unit_id' => @unit.id,
        'title' => 'Native request', 'requester_id' => 1, 'status_id' => 1, 'priority_id' => 1, 'description' => 'Native description')
    end
  end
end
