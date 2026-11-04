# frozen_string_literal: true

class JrcNico::Helpdesk::GlpiActions
  def self.prepare_binding(access, name, arguments)
    access.authorize!
    context = { account: access.account, user: access.user, account_user: access.membership }
    glpi = if name == 'create_glpi_ticket'
             JrcServiceDesk::Glpi::Destination.new(arguments.fetch('destination')).access!(context)
           else
             value = JrcServiceDesk::Glpi::Access.new(context).ready!
             JrcServiceDesk::Glpi::Reference.new(arguments.fetch('reference')).authorize_local!(access: value, operational: true)
           end
    { 'glpi_account_id' => access.account.id, 'glpi_connection_id' => glpi.connection.id,
      'glpi_connection_version' => glpi.connection.lock_version }
  end

  def self.validate_binding!(access, command)
    access.authorize!
    glpi = JrcServiceDesk::Glpi::Access.new(account: access.account, user: access.user, account_user: access.membership).ready!
    binding = command.execution_context
    unless binding['glpi_account_id'].to_s == access.account.id.to_s && binding['glpi_connection_id'].to_s == glpi.connection.id.to_s &&
           binding.key?('glpi_connection_version')
      raise Pundit::NotAuthorizedError
    end
    unless binding['glpi_connection_version'] == glpi.connection.lock_version && glpi.connection.primary_source?
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end
    true
  end

  def initialize(access, command: nil)
    @access = access.authorize!
    @context = { account: access.account, user: access.user, account_user: access.membership }
    @command = command
  end

  def call(name, arguments)
    JrcNico::ToolCatalog.new(@access).validate!(name, arguments)
    return search(arguments) if name == 'search_glpi_tickets'
    if name == 'create_glpi_ticket'
      approved_command!(name, arguments)
      return receipt_result(JrcServiceDesk::Glpi::AutomationCommand.new(authorizer: -> { approved_command!(name, arguments) }).create(user_context: @context,
        destination: arguments.fetch('destination'), attributes: arguments.fetch('attributes'), idempotency_key: request_key))
    end
    ref = JrcServiceDesk::Glpi::Reference.new(arguments.fetch('reference'))
    if name == 'read_glpi_reference'
      access = JrcServiceDesk::Glpi::Access.new(@context).ready!
      return JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
        row = ref.authorize!(access: access, client: client)
        record = ref.record!(access: access, client: client)
        { reference: record.reference, record: JrcServiceDesk::Glpi::ResourceQuery.new.normalize(row),
          resource_type: record.class.name, id: record.id, resources: [[record.class.name, record.id]], source: 'glpi' }
      end
    end
    approved_command!(name, arguments)
    if name == 'execute_glpi_operation'
      receipt = JrcServiceDesk::Glpi::AutomationCommand.new(authorizer: -> { approved_command!(name, arguments) }).call(user_context: @context, reference: ref.values,
        operation: arguments.fetch('operation'), attributes: arguments.fetch('attributes', {}),
        target_id: arguments['target_id'], expected_version: arguments['expected_version'], reason: arguments['reason'],
        idempotency_key: request_key)
      receipt_result(receipt)
    else
      local = if name == 'link_glpi_conversation'
                { conversation_id: @access.conversation(arguments.fetch('conversation_id')).id }
              else
                { incident_id: arguments.fetch('incident_id') }
              end
      link = JrcServiceDesk::Glpi::LinkLocalReference.new(authorizer: -> { approved_command!(name, arguments) })
        .call(user_context: @context, reference: ref.values, **local)
      { source: 'glpi', reference: link.glpi_reference.reference, link_id: link.id,
        resources: [[link.glpi_reference.class.name, link.glpi_reference_id]], message: 'Referência GLPI vinculada.' }
    end
  end

  private

  def request_key
    "nico_#{@command.id}_#{@command.request_id}"
  end

  def receipt_result(receipt)
    { command: receipt, source: 'glpi', message: "GLPI: #{receipt[:state]}",
      resources: [['JrcServiceDesk::GlpiCommand', receipt[:id].to_i]] }
  end

  def search(arguments)
    access = JrcServiceDesk::Glpi::Access.new(@context).ready!
    JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
      page = JrcServiceDesk::Glpi::TicketQuery.new(access, arguments.merge('per_page' => 20)).page(client)
      resources = []
      items = page.fetch(:items).map do |item|
        id = JrcServiceDesk::Input.id(item.fetch('id'))
        row = client.get("Ticket/#{id}")
        access.authorize_ticket!(client, row)
        raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless row['id'].to_s == id.to_s

        ref = JrcServiceDesk::Glpi::Reference.new('account_id' => access.context.account.id, 'connection_id' => access.connection.id,
          'itemtype' => 'Ticket', 'remote_id' => id, 'entity_id' => row.fetch('entities_id'))
        record = ref.record!(access: access, client: client)
        resources << [record.class.name, record.id]
        { reference: record.reference, name: JrcServiceDesk::Glpi::Normalize.text(row['name']),
          status: row['status'], priority: row['priority'], date_mod: row['date_mod'] }
      end
      { source: 'glpi', items: items, meta: page[:meta], resources: resources, bulk_content: false }
    end
  end

  def approved_command!(name, arguments)
    @access.authorize!
    @command&.reload
    unless @command&.persisted? && @command.session.account_id == @access.account.id && @command.session.user_id == @access.user.id &&
           @command.status == 'executing' && @command.approved_at && !@command.source_notice_id &&
           @command.execution_context.dig('authorization', 'source') == 'operator' &&
           @command.tool == name && @command.arguments == arguments &&
           @command.execution_context.dig('authorization', 'user_id').to_s == @access.user.id.to_s
      raise Pundit::NotAuthorizedError
    end
    self.class.validate_binding!(@access, @command)
  end
end
