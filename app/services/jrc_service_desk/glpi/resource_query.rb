# frozen_string_literal: true

class JrcServiceDesk::Glpi::ResourceQuery
  ENTITY_TYPES = { 'problems' => 'Problem', 'changes' => 'Change', 'categories' => 'ITILCategory', 'templates' => 'TicketTemplate',
                   'groups' => 'Group', 'suppliers' => 'Supplier', 'sla' => 'SLA', 'calendars' => 'Calendar',
                   'solution_types' => 'SolutionType', 'task_categories' => 'TaskCategory' }.freeze
  CHILD_TYPES = { 'tasks' => 'TicketTask', 'followups' => 'ITILFollowup', 'solutions' => 'ITILSolution',
                  'validations' => 'TicketValidation', 'actors' => 'Ticket_User', 'actor_groups' => 'Group_Ticket',
                  'actor_suppliers' => 'Supplier_Ticket', 'documents' => 'Document_Item', 'assets' => 'Item_Ticket',
                  'problem_links' => 'Problem_Ticket', 'change_links' => 'Change_Ticket', 'knowledge_links' => 'KnowbaseItem_Item',
                  'history' => 'Log', 'satisfaction' => 'TicketSatisfaction' }.freeze
  POLYMORPHIC = %w[ITILFollowup ITILSolution Document_Item KnowbaseItem_Item Log].freeze
  ASSET_TYPES = %w[Computer Monitor NetworkEquipment Peripheral Phone Printer Software].freeze
  PUBLIC_FIELDS = %w[id name content answer comment date date_mod date_creation begin end status state type priority urgency impact
                     entities_id tickets_id items_id itemtype users_id users_id_tech users_id_validate groups_id groups_id_tech
                     suppliers_id documents_id problems_id changes_id knowbaseitems_id itilcategories_id taskcategories_id
                     actiontime is_private filename mime tag realname firstname comment_submission comment_validation
                     submission_date validation_date satisfaction comment_satisfaction date_answer time_to_resolve time_to_own
                     slas_id_ttr slas_id_tto old_value new_value field date_creation num value tickettemplates_id].freeze
  CAPABILITIES = { 'tasks' => :tasks_view, 'validations' => :approvals_view, 'followups' => :notes_view,
                   'history' => :history_view, 'satisfaction' => :dashboard_view, 'problems' => :incidents_manage,
                   'changes' => :incidents_manage }.freeze

  def initialize
    @parents = {}
  end

  def call(access:, client:, kind:, filters:)
    access = authorize_kind!(access, kind)
    values = JrcServiceDesk::Input.attributes(filters, %w[page per_page search ticket_id parent_type])
    if values['ticket_id'].present?
      return related(access: access, client: client, kind: kind, ticket_id: values['ticket_id'],
                     parent_type: values.fetch('parent_type', 'Ticket'))
    end
    type = resource_type(kind)
    page = JrcServiceDesk::Input.id(values.fetch('page', 1))
    size = JrcServiceDesk::Input.id(values.fetch('per_page', 25))
    raise ArgumentError unless size <= 100 && page <= 100_000

    search = values.fetch('search', '')
    raise ArgumentError unless search.is_a?(String) && search.length <= 200

    found = 0
    items = []
    errors = []
    client.collection("#{type}/", 'sort' => 'id', 'order' => 'ASC').each do |row|
      begin
        authorize_record!(access, client, type, row)
        next if private?(access, row)

        normalized = normalize(row)
        next if search.present? && !%w[name content answer realname firstname].any? { |field| normalized[field].to_s.downcase.include?(search.downcase) }

        items << normalized if found >= (page - 1) * size && items.size < size
        found += 1
      rescue Pundit::NotAuthorizedError
        # Records outside the local unit/actor scope are excluded, never disclosed.
        next
      rescue JrcServiceDesk::Glpi::Error => e
        errors << e.code
      end
    end
    { items: items, meta: { page: page, per_page: size, total: found }, coverage: coverage(errors) }
  end

  def find(access:, client:, kind:, id:)
    normalize(raw(access: access, client: client, kind: kind, id: id))
  end

  # Backend-only raw lookup; callers cannot provide a remote type or URL.
  def raw(access:, client:, kind:, id:)
    access = authorize_kind!(access, kind)
    type = resource_type(kind)
    id = JrcServiceDesk::Input.id(id)
    row = client.get("#{type}/#{id}")
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless row.is_a?(Hash) && row['id'].to_s == id.to_s

    authorize_record!(access, client, type, row)
    raise Pundit::NotAuthorizedError if private?(access, row)

    @parents[[type, id]] = row if %w[Ticket Problem Change].include?(type)
    row
  end

  def related(access:, client:, kind:, ticket_id:, parent_type: 'Ticket')
    access = authorize_kind!(access, kind)
    raise ArgumentError unless %w[Ticket Problem Change].include?(parent_type)

    id = JrcServiceDesk::Input.id(ticket_id)
    parent!(access, client, parent_type, id)
    type = CHILD_TYPES.fetch(kind)
    if kind == 'tasks' && parent_type != 'Ticket'
      type = "#{parent_type}Task"
    elsif kind == 'validations' && parent_type != 'Ticket'
      type = "#{parent_type}Validation"
    elsif kind == 'actors' && parent_type != 'Ticket'
      type = "#{parent_type}_User"
    elsif kind == 'actor_groups' && parent_type != 'Ticket'
      type = "#{parent_type}_Group"
    elsif parent_type != 'Ticket' && !POLYMORPHIC.include?(type)
      raise JrcServiceDesk::Glpi::Error.new('unsupported_relation', 422)
    end
    rows = client.collection("#{parent_type}/#{id}/#{type}/").map do |row|
      check_parent!(type, row, parent_type, id)
      normalize(row) unless private?(access, row)
    end.compact
    { items: rows, coverage: coverage([]), meta: { total: rows.size } }
  end

  def authorize_record!(access, client, type, row)
    access = bind_access!(access)
    if type == 'Ticket'
      access.authorize_ticket!(client, row)
    elsif ENTITY_TYPES.value?(type) || ASSET_TYPES.include?(type)
      access.unit_for(JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('entities_id')))
    elsif type == 'KnowbaseItem'
      id = JrcServiceDesk::Input.id(row.fetch('id'))
      visible = client.collection("KnowbaseItem/#{id}/Entity_KnowbaseItem/").any? do |link|
        raise Pundit::NotAuthorizedError unless link['knowbaseitems_id'].to_s == id.to_s

        access.entity_ids.include?(JrcServiceDesk::Glpi::Identifiers.remote(link.fetch('entities_id')))
      end
      raise Pundit::NotAuthorizedError unless visible
    elsif type == 'User'
      id = JrcServiceDesk::Input.id(row.fetch('id'))
      visible = client.collection("User/#{id}/Profile_User/").any? do |link|
        raise Pundit::NotAuthorizedError unless link['users_id'].to_s == id.to_s

        access.entity_ids.include?(JrcServiceDesk::Glpi::Identifiers.remote(link.fetch('entities_id')))
      end
      raise Pundit::NotAuthorizedError unless visible
    elsif CHILD_TYPES.value?(type)
      parent_type = POLYMORPHIC.include?(type) ? row.fetch('itemtype') : 'Ticket'
      raise Pundit::NotAuthorizedError unless %w[Ticket Problem Change].include?(parent_type)

      field = POLYMORPHIC.include?(type) ? 'items_id' : 'tickets_id'
      parent!(access, client, parent_type, JrcServiceDesk::Input.id(row.fetch(field)))
    else
      raise ArgumentError
    end
  end

  def normalize(row)
    row.slice(*PUBLIC_FIELDS).transform_values { |value| value.is_a?(String) ? JrcServiceDesk::Glpi::Normalize.text(value) : value }
  end

  private

  def resource_type(kind)
    ({ 'tickets' => 'Ticket', 'users' => 'User', 'knowledge' => 'KnowbaseItem' }.merge(ENTITY_TYPES).merge(CHILD_TYPES)).fetch(kind)
  end

  def authorize_kind!(access, kind)
    access = bind_access!(access)
    raise Pundit::NotAuthorizedError unless access.context.capability?(CAPABILITIES.fetch(kind, :tickets_view))

    access
  end

  def bind_access!(access)
    fresh = JrcServiceDesk::Glpi::Access.new(access.context.to_h).ready!
    unless fresh.connection.id == access.connection.id && fresh.connection.lock_version == access.connection.lock_version
      raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409)
    end
    identity = [fresh.context.account.id, fresh.connection.id, fresh.connection.lock_version, fresh.context.account_user.id,
                fresh.entity_ids, fresh.glpi_user_id, fresh.all_tickets?, fresh.context.effective_capabilities]
    @parents.clear unless @identity == identity
    @identity = identity
    fresh
  end

  def parent!(access, client, type, id)
    return @parents[[type, id]] if @parents.key?([type, id])

    raw(access: access, client: client, kind: { 'Ticket' => 'tickets', 'Problem' => 'problems', 'Change' => 'changes' }.fetch(type), id: id)
  end

  def check_parent!(type, row, parent_type, id)
    field = POLYMORPHIC.include?(type) ? 'items_id' : "#{parent_type.downcase}s_id"
    raise Pundit::NotAuthorizedError unless row[field].to_s == id.to_s
    raise Pundit::NotAuthorizedError if POLYMORPHIC.include?(type) && row['itemtype'] != parent_type
  end

  def private?(access, row)
    !access.context.administrator? && [1, '1', true].include?(row['is_private'])
  end

  def coverage(errors)
    { complete: errors.empty?, errors: errors.tally, observed_at: Time.current.iso8601, source: 'glpi', atomic_snapshot: false }
  end
end
