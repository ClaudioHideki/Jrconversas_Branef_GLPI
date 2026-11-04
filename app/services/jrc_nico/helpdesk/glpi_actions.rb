# frozen_string_literal: true

class JrcNico::Helpdesk::GlpiActions
  def initialize(access, command: nil)
    @access = access.authorize!
    @context = { account: access.account, user: access.user, account_user: access.membership }
    @command = command
  end

  def call(name, arguments)
    JrcNico::ToolCatalog.new(@access).validate!(name, arguments)
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
      receipt = JrcServiceDesk::Glpi::AutomationCommand.new.call(user_context: @context, reference: ref.values,
        operation: arguments.fetch('operation'), attributes: arguments.fetch('attributes', {}),
        target_id: arguments['target_id'], expected_version: arguments['expected_version'], reason: arguments['reason'],
        idempotency_key: "nico_#{@command.id}_#{@command.request_id}")
      { command: receipt, source: 'glpi', message: "GLPI: #{receipt[:state]}",
        resources: [['JrcServiceDesk::GlpiCommand', receipt[:id].to_i]] }
    else
      local = if name == 'link_glpi_conversation'
                { conversation_id: @access.conversation(arguments.fetch('conversation_id')).id }
              else
                { incident_id: arguments.fetch('incident_id') }
              end
      link = JrcServiceDesk::Glpi::LinkLocalReference.new.call(user_context: @context, reference: ref.values, **local)
      { source: 'glpi', reference: link.glpi_reference.reference, link_id: link.id,
        resources: [[link.glpi_reference.class.name, link.glpi_reference_id]], message: 'Referência GLPI vinculada.' }
    end
  end

  private

  def approved_command!(name, arguments)
    @command&.reload
    unless @command&.persisted? && @command.session.account_id == @access.account.id && @command.session.user_id == @access.user.id &&
           @command.status == 'executing' && @command.approved_at && !@command.source_notice_id &&
           @command.execution_context.dig('authorization', 'source') == 'operator' &&
           @command.tool == name && @command.arguments == arguments &&
           @command.execution_context.dig('authorization', 'user_id').to_s == @access.user.id.to_s
      raise Pundit::NotAuthorizedError
    end
  end
end
