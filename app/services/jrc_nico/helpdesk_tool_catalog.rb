class JrcNico::HelpdeskToolCatalog
  TOOLS = {
    'search_glpi_tickets' => ['Consultar até 20 chamados GLPI por página e 20 páginas; refine filtros para continuar. Somente metadados e referências; não copia descrições à IA',
      'service_desk_helpdesk', false, %w[entity_id search status priority page]],
    'create_glpi_ticket' => ['Preparar criação GLPI no destino connection_id/connection_version/entity_id autorizado. attributes: name/content/type/urgency/impact; exige confirmação humana',
      'service_desk_helpdesk', true, %w[destination* attributes*]],
    'read_glpi_reference' => ['Consultar somente o registro GLPI explicitamente identificado e autorizado, sem enviar a base inteira à IA',
      'service_desk_helpdesk', false, %w[reference*]],
    'execute_glpi_operation' => ['Preparar uma operação GLPI tipada com usuário técnico e auditoria JRC; exige confirmação humana e versão consultada',
      'service_desk_helpdesk', true, %w[reference* operation* attributes expected_version reason target_id]],
    'link_glpi_conversation' => ['Vincular referência GLPI à conversa autorizada; conversation_id é display_id, sem criar chamado nativo',
      'service_desk_helpdesk', true, %w[reference* conversation_id*]],
    'link_glpi_case' => ['Vincular referência GLPI a um caso local histórico autorizado, sem alterar seu estado',
      'service_desk_helpdesk', true, %w[reference* incident_id*]],
    'read_service_ticket_tasks' => ['Consultar tarefas visíveis do chamado, sem totais globais', 'service_desk_helpdesk', false, %w[ticket_id* page]],
    'create_service_ticket_task' => ['Criar tarefa interna do chamado com prazo, responsável e checklist explícitos', 'service_desk_helpdesk', true,
                                     %w[ticket_id* title* description due_at priority assignee_account_user_id checklist]],
    'read_service_ticket_approvals' => ['Consultar aprovações internas visíveis do chamado; não decide pelo aprovador',
                                        'service_desk_helpdesk', false, %w[ticket_id* page]],
    'read_service_incident' => ['Consultar incidente nativo e chamados autorizados', 'service_desk_helpdesk', false, %w[incident_id*]],
    'create_service_incident' => ['Criar incidente nativo e vincular chamados autorizados da mesma unidade', 'service_desk_helpdesk', true,
                                  %w[unit_id* title* severity* description ticket_ids*]],
    'prepare_incident_campaign' => ['Prepare only a reviewed draft for the exact incident requester cohort; never launch',
      'service_desk_helpdesk', true, %w[event_id* incident_id* inbox_id* name* source_digest*]],
    'prepare_closed_case_knowledge' => ['Prepare an explicitly human-generalized private knowledge draft; never approve or publish',
      'service_desk_helpdesk', true, %w[event_id* closed_transition_id* title* body* generalization_reviewed* source_digest*]]
  }.freeze
  CAPABILITIES = {
    'search_glpi_tickets' => :tickets_view, 'create_glpi_ticket' => :tickets_create,
    'read_glpi_reference' => :tickets_view, 'execute_glpi_operation' => :tickets_view,
    'link_glpi_conversation' => :conversations_link, 'link_glpi_case' => :incidents_manage,
    'read_service_ticket_tasks' => :tasks_view, 'create_service_ticket_task' => :tasks_manage,
    'read_service_ticket_approvals' => :approvals_view, 'read_service_incident' => :incidents_manage,
    'create_service_incident' => :incidents_manage, 'prepare_incident_campaign' => :incidents_manage,
    'prepare_closed_case_knowledge' => :history_view
  }.freeze
  BOOLEAN_VALUES = [true, false].freeze
  GLPI_TOOLS = %w[search_glpi_tickets create_glpi_ticket read_glpi_reference execute_glpi_operation link_glpi_conversation link_glpi_case].freeze
  GLPI_MUTATIONS = GLPI_TOOLS - %w[read_glpi_reference search_glpi_tickets]

  def self.available?(access, name)
    selected = JrcServiceDesk::NativeSourceGuard.selected_glpi?(access.account)
    return false if GLPI_TOOLS.include?(name) != selected
    context = JrcServiceDesk::OperationalContext.new(account: access.account, user: access.user, account_user: access.membership)
    allowed = context.capability?(:module_view) && context.capability?(CAPABILITIES.fetch(name))
    allowed &&= context.administrator? if %w[prepare_incident_campaign prepare_closed_case_knowledge].include?(name)
    allowed &&= access.campaigns? if name == 'prepare_incident_campaign'
    allowed
  end

  def self.valid_value?(key, value, tool: nil)
    case key
    when 'destination'
      JrcServiceDesk::Glpi::Destination.new(value)
      true
    when 'entity_id'
      JrcServiceDesk::Glpi::Identifiers.remote(value)
      true
    when 'status', 'priority'
      if GLPI_TOOLS.include?(tool)
        value.is_a?(Integer) && value.between?(1, 6)
      elsif key == 'priority'
        %w[low normal high urgent].include?(value)
      end
    when 'reference'
      JrcServiceDesk::Glpi::Reference.new(value)
      true
    when 'attributes'
      value.is_a?(Hash) && JrcServiceDesk::CanonicalJson.dump(value).bytesize <= 65_536
    when 'operation' then JrcServiceDesk::Glpi::OperationCatalogue::OPERATIONS.key?(value)
    when 'expected_version' then value.is_a?(String) && value.length.between?(1, 100)
    when 'generalization_reviewed' then value == true
    when 'source_digest' then value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
    when 'ticket_ids' then ticket_ids?(value)
    when 'checklist' then checklist?(value)
    when 'severity' then %w[low normal high critical].include?(value)
    when 'due_at' then date?(value)
    end
  rescue ArgumentError
    false
  end

  def self.ticket_ids?(value)
    value.is_a?(Array) && value.size.between?(1, 200) && value.uniq == value && value.all? { |id| id.is_a?(Integer) && id.positive? }
  end

  def self.checklist?(value)
    value.is_a?(Array) && value.size <= 100 && value.all? { |item| checklist_item?(item) }
  end

  def self.checklist_item?(item)
    item.is_a?(Hash) && item.keys.sort == %w[done title] && item['title'].is_a?(String) &&
      item['title'].strip.size.between?(1, 500) && BOOLEAN_VALUES.include?(item['done'])
  end

  def self.date?(value)
    value.is_a?(String) && value.size <= 60 && Time.iso8601(value).present?
  end
end
