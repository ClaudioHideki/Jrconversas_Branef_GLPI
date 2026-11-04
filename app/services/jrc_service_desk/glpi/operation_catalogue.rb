# frozen_string_literal: true

# Public operations are named contracts, never caller-selected remote paths or classes.
class JrcServiceDesk::Glpi::OperationCatalogue
  TICKET_FIELDS = %w[name content type urgency impact itilcategories_id].freeze
  TASK_FIELDS = %w[content is_private actiontime begin end state users_id_tech groups_id_tech taskcategories_id].freeze
  ITIL_FIELDS = %w[name content status urgency impact priority itilcategories_id _users_id_assign _groups_id_assign].freeze
  ARTICLE_FIELDS = %w[name answer is_faq knowbaseitemcategories_id begin_date end_date].freeze
  CATEGORY_FIELDS = %w[name comment itilcategories_id entities_id is_recursive is_incident is_request is_problem is_change].freeze
  TEMPLATE_FIELDS = %w[name comment entities_id is_recursive].freeze
  GROUP_RELATIONS = { 'Ticket' => 'Group_Ticket', 'Problem' => 'Group_Problem', 'Change' => 'Change_Group' }.freeze

  OPERATIONS = {}.tap do |operations|
    add = lambda do |key, type, verb, capability, fields, options = {}|
      operations[key] = { type: type, verb: verb, capability: capability, fields: fields.freeze,
        required: [], defaults: {}, parent: nil, parent_field: nil, admin: false, source_right: ['ticket', 2],
        source_alternatives: [] }.merge(options).freeze
    end
    add.call('ticket.create', 'Ticket', 'post', 'tickets_create', TICKET_FIELDS + %w[entities_id priority _users_id_requester],
             required: %w[name content type urgency impact], source_right: ['ticket', 4])
    add.call('ticket.update', 'Ticket', 'patch', 'tickets_edit', TICKET_FIELDS)
    add.call('ticket.assign', 'Ticket', 'patch', 'tickets_assign', %w[_users_id_assign _groups_id_assign], source_right: ['ticket', 8192])
    add.call('ticket.transfer', 'Ticket', 'patch', 'tickets_transfer', %w[entities_id _users_id_assign _groups_id_assign],
             required: %w[entities_id])
    add.call('ticket.priority', 'Ticket', 'patch', 'priority_change', %w[priority], required: %w[priority], source_right: ['ticket', 65536])
    { 'pause' => ['pause', 4], 'resume' => ['resume', 2], 'close' => ['close', 6], 'reopen' => ['reopen', 2] }.each do |key, values|
      add.call("ticket.#{key}", 'Ticket', 'patch', values[0], [], defaults: { 'status' => values[1] })
    end
    add.call('ticket.solve', 'ITILSolution', 'post', 'resolve', %w[content solutiontypes_id],
             parent: 'Ticket', parent_field: 'items_id', required: %w[content], defaults: { 'itemtype' => 'Ticket' })
    add.call('ticket.delete', 'Ticket', 'delete', 'cancel', [], admin: true, source_right: ['ticket', 8])
    add.call('ticket.restore', 'Ticket', 'patch', 'cancel', [], admin: true,
             defaults: { 'is_deleted' => 0 }, source_right: ['ticket', 8])
    { 'followup' => ['ITILFollowup', 'notes_add', %w[content is_private], 'followup', 22532, 1026],
      'task' => ['TicketTask', 'tasks_manage', TASK_FIELDS, 'task', 4096, 1024] }.each do |key, values|
      type, capability, fields, right, create_mask, update_mask = values
      %w[create update delete].each do |verb|
        add.call("#{key}.#{verb}", type, { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
                 capability, verb == 'delete' ? [] : fields, parent: 'Ticket', required: verb == 'create' ? %w[content] : [],
                 parent_field: key == 'followup' ? 'items_id' : 'tickets_id',
                 defaults: key == 'followup' ? { 'itemtype' => 'Ticket' } : {},
                 source_right: [right, verb == 'create' ? create_mask : verb == 'delete' ? 16 : update_mask],
                 source_alternatives: key == 'task' && verb != 'delete' ? [['ticket', 32768]] : [])
      end
    end
    add.call('validation.request', 'TicketValidation', 'post', 'approvals_request', %w[users_id_validate comment_submission],
             parent: 'Ticket', parent_field: 'tickets_id', required: %w[users_id_validate comment_submission], source_right: ['ticketvalidation', 3072])
    add.call('validation.decide', 'TicketValidation', 'patch', 'approvals_decide', %w[status comment_validation],
             parent: 'Ticket', parent_field: 'tickets_id', required: %w[status comment_validation], source_right: ['ticketvalidation', 12288])
    { 'actor' => ['Ticket_User', %w[users_id type]], 'group' => ['Group_Ticket', %w[groups_id type]],
      'supplier' => ['Supplier_Ticket', %w[suppliers_id type]], 'asset' => ['Item_Ticket', %w[itemtype items_id]],
      'problem_link' => ['Problem_Ticket', %w[problems_id]], 'change_link' => ['Change_Ticket', %w[changes_id]],
      'knowledge_link' => ['KnowbaseItem_Item', %w[knowbaseitems_id]], 'document_link' => ['Document_Item', %w[documents_id]] }.each do |key, values|
      %w[create delete].each do |verb|
        capability = %w[problem_link change_link].include?(key) ? 'incidents_manage' : 'tickets_assign'
        add.call("#{key}.#{verb}", values[0], verb == 'create' ? 'post' : 'delete', capability,
                 verb == 'create' ? values[1] : [], parent: 'Ticket', required: verb == 'create' ? values[1] : [],
                 parent_field: %w[knowledge_link document_link].include?(key) ? 'items_id' : 'tickets_id',
                 defaults: %w[knowledge_link document_link].include?(key) ? { 'itemtype' => 'Ticket' } : {})
      end
    end
    { 'problem' => 'Problem', 'change' => 'Change' }.each do |key, type|
      %w[create update delete].each do |verb|
        add.call("#{key}.#{verb}", type, { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
                 'incidents_manage', verb == 'delete' ? [] : ITIL_FIELDS, admin: verb == 'delete',
                 required: verb == 'create' ? %w[name content] : [], source_right: [key, verb == 'create' ? 4 : verb == 'delete' ? 8 : 2])
      end
      add.call("#{key}.assign", type, 'patch', 'incidents_manage', %w[_users_id_assign _groups_id_assign], source_right: [key, 2])
      add.call("#{key}.priority", type, 'patch', 'incidents_manage', %w[priority], required: %w[priority], source_right: [key, 2])
      { 'pause' => 4, 'resume' => key == 'change' ? 9 : 2, 'close' => 6, 'reopen' => key == 'change' ? 9 : 2 }.each do |verb, status|
        add.call("#{key}.#{verb}", type, 'patch', 'incidents_manage', [], defaults: { 'status' => status }, source_right: [key, 2])
      end
      add.call("#{key}.solve", 'ITILSolution', 'post', 'incidents_manage', %w[content solutiontypes_id],
               parent: type, parent_field: 'items_id', required: %w[content], defaults: { 'itemtype' => type }, source_right: [key, 2])
      { 'task' => ["#{type}Task", TASK_FIELDS, "#{key}s_id"],
        'followup' => ['ITILFollowup', %w[content is_private], 'items_id'],
        'actor' => ["#{type}_User", %w[users_id type], "#{key}s_id"],
        'group' => [GROUP_RELATIONS.fetch(type), %w[groups_id type], "#{key}s_id"] }.each do |family, data|
        %w[create update delete].each do |verb|
          next if %w[actor group].include?(family) && verb == 'update'

          add.call("#{key}_#{family}.#{verb}", data[0], { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
                   'incidents_manage', verb == 'delete' ? [] : data[1], parent: type, parent_field: data[2],
                   required: verb == 'create' ? (%w[actor group].include?(family) ? data[1] : %w[content]) : [],
                   defaults: family == 'followup' ? { 'itemtype' => type } : {}, source_right: [key, 2])
        end
      end
      if key == 'change'
        add.call('change_validation.request', 'ChangeValidation', 'post', 'incidents_manage', %w[users_id_validate comment_submission],
                 parent: type, parent_field: 'changes_id', required: %w[users_id_validate comment_submission], source_right: ['changevalidation', 4])
        add.call('change_validation.decide', 'ChangeValidation', 'patch', 'incidents_manage', %w[status comment_validation],
                 parent: type, parent_field: 'changes_id', required: %w[status comment_validation], source_right: ['changevalidation', 1024])
      end
    end
    %w[create update delete].each do |verb|
      add.call("knowledge.#{verb}", 'KnowbaseItem', { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
               'settings_view', verb == 'delete' ? [] : ARTICLE_FIELDS, admin: true,
               required: verb == 'create' ? %w[name answer] : [], source_right: ['knowbase', verb == 'create' ? 4 : verb == 'delete' ? 16 : 2])
    end
    { 'category' => ['ITILCategory', CATEGORY_FIELDS, 'itilcategory'],
      'template' => ['TicketTemplate', TEMPLATE_FIELDS, 'tickettemplate'] }.each do |key, values|
      %w[create update delete].each do |verb|
        add.call("#{key}.#{verb}", values[0], { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
                 'categories_manage', verb == 'delete' ? [] : values[1], admin: true,
                 required: verb == 'create' ? %w[name] : [], source_right: [values[2], verb == 'create' ? 4 : verb == 'delete' ? 16 : 2])
      end
    end
    %w[Mandatory Hidden Predefined].each do |kind|
      %w[create delete].each do |verb|
        fields = %w[num] + (kind == 'Predefined' ? %w[value] : [])
        add.call("template_#{kind.downcase}.#{verb}", "TicketTemplate#{kind}Field", verb == 'create' ? 'post' : 'delete',
                 'categories_manage', verb == 'create' ? fields : [], admin: true,
                 parent: 'TicketTemplate', parent_field: 'tickettemplates_id',
                 required: verb == 'create' ? fields : [], source_right: ['tickettemplate', 2])
      end
    end
  end.freeze

  def self.fetch(operation)
    OPERATIONS.fetch(operation)
  end
end
