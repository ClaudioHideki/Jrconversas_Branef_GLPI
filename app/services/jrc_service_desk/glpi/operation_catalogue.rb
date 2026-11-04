# frozen_string_literal: true

# Public operations are named contracts, never caller-selected remote paths or classes.
class JrcServiceDesk::Glpi::OperationCatalogue
  TICKET_FIELDS = %w[name content type urgency impact itilcategories_id].freeze
  TASK_FIELDS = %w[content is_private actiontime begin end state users_id_tech groups_id_tech taskcategories_id].freeze
  ITIL_FIELDS = %w[name content status urgency impact priority itilcategories_id _users_id_assign _groups_id_assign].freeze
  ARTICLE_FIELDS = %w[name answer is_faq knowbaseitemcategories_id begin_date end_date].freeze
  CATEGORY_FIELDS = %w[name comment itilcategories_id entities_id is_recursive is_incident is_request is_problem is_change].freeze
  TEMPLATE_FIELDS = %w[name comment entities_id is_recursive].freeze

  OPERATIONS = {}.tap do |operations|
    add = lambda do |key, type, verb, capability, fields, options = {}|
      operations[key] = { type: type, verb: verb, capability: capability, fields: fields.freeze,
        required: [], defaults: {}, parent: nil, admin: false, source_right: ['ticket', 2] }.merge(options).freeze
    end
    add.call('ticket.create', 'Ticket', 'post', 'tickets_create', TICKET_FIELDS + %w[entities_id priority _users_id_requester],
             required: %w[name content type urgency impact], source_right: ['ticket', 4])
    add.call('ticket.update', 'Ticket', 'patch', 'tickets_edit', TICKET_FIELDS)
    add.call('ticket.assign', 'Ticket', 'patch', 'tickets_assign', %w[_users_id_assign _groups_id_assign])
    add.call('ticket.transfer', 'Ticket', 'patch', 'tickets_transfer', %w[entities_id _users_id_assign _groups_id_assign],
             required: %w[entities_id])
    add.call('ticket.priority', 'Ticket', 'patch', 'priority_change', %w[priority], required: %w[priority])
    { 'pause' => ['pause', 4], 'resume' => ['resume', 2], 'close' => ['close', 6], 'reopen' => ['reopen', 2] }.each do |key, values|
      add.call("ticket.#{key}", 'Ticket', 'patch', values[0], [], defaults: { 'status' => values[1] })
    end
    add.call('ticket.solve', 'ITILSolution', 'post', 'resolve', %w[content solutiontypes_id],
             parent: 'Ticket', required: %w[content], defaults: { 'itemtype' => 'Ticket' })
    add.call('ticket.delete', 'Ticket', 'delete', 'cancel', [], admin: true, source_right: ['ticket', 8])
    add.call('ticket.restore', 'Ticket', 'patch', 'cancel', [], admin: true,
             defaults: { 'is_deleted' => 0 }, source_right: ['ticket', 8])
    { 'followup' => ['ITILFollowup', 'notes_add', %w[content is_private], 'followup', 4100, 1026],
      'task' => ['TicketTask', 'tasks_manage', TASK_FIELDS, 'task', 4100, 1026] }.each do |key, values|
      type, capability, fields, right, create_mask, update_mask = values
      %w[create update delete].each do |verb|
        add.call("#{key}.#{verb}", type, { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
                 capability, verb == 'delete' ? [] : fields, parent: 'Ticket', required: verb == 'create' ? %w[content] : [],
                 source_right: [right, verb == 'create' ? create_mask : verb == 'delete' ? 16 : update_mask])
      end
    end
    add.call('validation.request', 'TicketValidation', 'post', 'approvals_request', %w[users_id_validate comment_submission],
             parent: 'Ticket', required: %w[users_id_validate comment_submission], source_right: ['ticketvalidation', 3072])
    add.call('validation.decide', 'TicketValidation', 'patch', 'approvals_decide', %w[status comment_validation],
             parent: 'Ticket', required: %w[status comment_validation], source_right: ['ticketvalidation', 12288])
    { 'actor' => ['Ticket_User', %w[users_id type]], 'group' => ['Group_Ticket', %w[groups_id type]],
      'supplier' => ['Supplier_Ticket', %w[suppliers_id type]], 'asset' => ['Item_Ticket', %w[itemtype items_id]],
      'problem_link' => ['Problem_Ticket', %w[problems_id]], 'change_link' => ['Change_Ticket', %w[changes_id]],
      'knowledge_link' => ['KnowbaseItem_Item', %w[knowbaseitems_id]], 'document_link' => ['Document_Item', %w[documents_id]] }.each do |key, values|
      %w[create delete].each do |verb|
        add.call("#{key}.#{verb}", values[0], verb == 'create' ? 'post' : 'delete', 'tickets_assign',
                 verb == 'create' ? values[1] : [], parent: 'Ticket', required: verb == 'create' ? values[1] : [])
      end
    end
    { 'problem' => 'Problem', 'change' => 'Change' }.each do |key, type|
      %w[create update delete].each do |verb|
        add.call("#{key}.#{verb}", type, { 'create' => 'post', 'update' => 'patch', 'delete' => 'delete' }.fetch(verb),
                 'incidents_manage', verb == 'delete' ? [] : ITIL_FIELDS, admin: verb == 'delete',
                 required: verb == 'create' ? %w[name content] : [], source_right: [key, verb == 'create' ? 4 : verb == 'delete' ? 8 : 2])
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
        fields = %w[tickettemplates_id num] + (kind == 'Predefined' ? %w[value] : [])
        add.call("template_#{kind.downcase}.#{verb}", "TicketTemplate#{kind}Field", verb == 'create' ? 'post' : 'delete',
                 'categories_manage', verb == 'create' ? fields : [], admin: true,
                 required: verb == 'create' ? fields : [], source_right: ['tickettemplate', 2])
      end
    end
  end.freeze

  def self.fetch(operation)
    OPERATIONS.fetch(operation)
  end
end
