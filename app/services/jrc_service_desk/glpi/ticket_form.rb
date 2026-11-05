# frozen_string_literal: true

# Reproduces GLPI 10's form policy using typed, authorized metadata, not Ticket.add defaults.
class JrcServiceDesk::Glpi::TicketForm
  FIELDS = %w[name content type urgency impact priority itilcategories_id _users_id_requester status].freeze
  STATUS_CAPABILITIES = { 2 => :tickets_assign, 3 => :tasks_manage, 4 => :pause, 5 => :resolve, 6 => :close }.freeze
  OPTION_FIELDS = {
    ['glpi_tickets', 'name'] => 'name', ['glpi_tickets', 'content'] => 'content',
    ['glpi_tickets', 'type'] => 'type', ['glpi_tickets', 'status'] => 'status',
    ['glpi_tickets', 'urgency'] => 'urgency', ['glpi_tickets', 'impact'] => 'impact', ['glpi_tickets', 'priority'] => 'priority',
    ['glpi_itilcategories', 'completename'] => 'itilcategories_id', ['glpi_items_tickets', 'items_id'] => 'items_id',
    ['glpi_documents', 'name'] => '_documents_id', ['glpi_requesttypes', 'name'] => 'requesttypes_id',
    ['glpi_locations', 'completename'] => 'locations_id', ['glpi_tasktemplates', 'name'] => '_tasktemplates_id',
    ['glpi_tickets', 'date'] => 'date', ['glpi_tickets', 'actiontime'] => 'actiontime',
    ['glpi_tickets', 'time_to_resolve'] => 'time_to_resolve', ['glpi_tickets', 'time_to_own'] => 'time_to_own'
  }.freeze
  ACTORS = { 4 => '_users_id_requester', 5 => '_users_id_assign', 8 => '_groups_id_assign',
    65 => '_groups_id_observer', 66 => '_users_id_observer', 71 => '_groups_id_requester', -2 => '_add_validation' }.freeze

  def self.missing?(value)
    value.nil? || value == 0 || value == false || (value.is_a?(String) && JrcServiceDesk::Glpi::Normalize.text(value).strip.empty?)
  end

  def call(access:, client:, filters:)
    values = JrcServiceDesk::Input.attributes(filters, %w[entity_id type category_id template_id])
    @entity = JrcServiceDesk::Glpi::Identifiers.remote(values.fetch('entity_id'))
    @access = JrcServiceDesk::Glpi::Execute.new.fresh_access(access)
    raise Pundit::NotAuthorizedError unless @access.context.capability?(:tickets_create)

    @access.unit_for(@entity)
    @client = client
    @scope = JrcServiceDesk::Glpi::MetadataScope.new(access: @access, client: client, entity_id: @entity)
    @type_supplied = values['type'].present?
    type = @type_supplied ? JrcServiceDesk::Input.id(values['type']) : entity_default_type
    raise ArgumentError unless [1, 2].include?(type)

    category_id = optional_id(values['category_id'])
    explicit = optional_id(values['template_id'])
    profile = client.get('getActiveProfile/').fetch('active_profile')
    raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) if (profile.fetch('ticket', 0).to_i & 4).zero?
    entities = client.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
    invalid! unless entities.is_a?(Array)
    permitted = entities.any? { |row| JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('id')) == @entity }
    raise JrcServiceDesk::Glpi::Error.new('operation_not_permitted', 403) unless permitted

    @options = client.get('listSearchOptions/Ticket/')
    invalid! unless @options.is_a?(Hash)
    category = category_id.positive? ? category!(category_id, type) : nil
    template, source = resolve(explicit, type, category, profile)
    result = build(template, source, type, category_id, profile)
    JrcServiceDesk::Glpi::Execute.new.fresh_access(@access).unit_for(@entity)
    result
  rescue KeyError, TypeError
    invalid!
  end

  # Template/category metadata may be inherited from an ancestor without granting
  # operational access to that ancestor's tickets. Only a recursive item applies.
  def scoped!(row)
    @scope.authorize!('TicketTemplate', row)
  end

  def validate_references!(input)
    if input['itilcategories_id'].to_i.positive?
      category!(input['itilcategories_id'], input.fetch('type'))
    end
    return unless input['_users_id_requester'].to_i.positive?

    id = JrcServiceDesk::Input.id(input['_users_id_requester'])
    row = @client.get("User/#{id}")
    invalid! unless row.is_a?(Hash) && row['id'].to_s == id.to_s
    @scope.authorize!('User', row)
  end

  private

  def resolve(explicit, type, category, profile)
    return [load_template(explicit, true), 'explicit'] if explicit.positive?

    if category && (id = category_template(category, type)).positive?
      return [load_template(id, false), 'category']
    end
    id = optional_id(profile.fetch('tickettemplates_id'))
    source = 'profile'
    unless id.positive?
      id = entity_template
      source = 'entity'
    end
    return [nil, 'none'] unless id.positive?

    template = load_template(id, true)
    new_type = template[:predefined].fetch('type', type)
    new_category = template[:predefined].fetch('itilcategories_id', category ? category.fetch('id').to_i : 0)
    if new_category.positive?
      category = category!(new_category, new_type)
      id = category_template(category, new_type)
      return [load_template(id, false), 'category_predefined'] if id.positive?
    end
    [template, source]
  end

  def entity_template
    id = @entity
    visited = []
    loop do
      invalid! if visited.include?(id) || visited.length >= 100
      visited << id
      row = @scope.entity(id)
      return optional_id(row.fetch('tickettemplates_id')) unless row.fetch('tickettemplates_strategy').to_s == '-2'
      return 0 if id.zero? || row['entities_id'].nil?

      id = JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('entities_id'))
    end
  end

  def entity_default_type
    id = @entity
    visited = []
    loop do
      invalid! if visited.include?(id) || visited.length >= 100
      visited << id
      row = @scope.entity(id)
      value = row.fetch('tickettype')
      unless value.to_s == '-2'
        number = JrcServiceDesk::Glpi::Identifiers.remote(value)
        invalid! unless [1, 2].include?(number)
        return number
      end
      return 1 if id.zero? || row['entities_id'].nil?

      id = JrcServiceDesk::Glpi::Identifiers.remote(row.fetch('entities_id'))
    end
  end

  def category!(id, type)
    id = JrcServiceDesk::Input.id(id)
    row = @client.get("ITILCategory/#{id}")
    invalid! unless row.is_a?(Hash) && row['id'].to_s == id.to_s
    @scope.authorize!('ITILCategory', row)
    flag = type.to_i == 1 ? 'is_incident' : 'is_request'
    raise Pundit::NotAuthorizedError unless [1, '1', true].include?(row.fetch(flag))

    row
  end

  def category_template(row, type)
    optional_id(row.fetch(type.to_i == 1 ? 'tickettemplates_id_incident' : 'tickettemplates_id_demand'))
  end

  def load_template(id, with_selectors)
    row = @client.get("TicketTemplate/#{id}")
    invalid! unless row.is_a?(Hash) && row['id'].to_s == id.to_s
    scoped!(row)
    result = { id: id, revision: row['date_mod'], required: [], hidden: [], predefined: {}, unsupported: [] }
    %w[Mandatory Hidden Predefined].each do |kind|
      entries = @client.collection("TicketTemplate/#{id}/TicketTemplate#{kind}Field/").to_a
      entries.sort_by { |rule| JrcServiceDesk::Input.id(rule.fetch('id')) }.each do |rule|
        raise Pundit::NotAuthorizedError unless rule['tickettemplates_id'].to_s == id.to_s

        field = field_name(rule.fetch('num'))
        next if kind != 'Mandatory' && !with_selectors && %w[type itilcategories_id].include?(field)

        if kind == 'Predefined'
          if FIELDS.include?(field)
            result[:predefined][field] = predefined_value(field, rule.fetch('value'))
          else
            result[:unsupported] << field
          end
        else
          result[kind == 'Mandatory' ? :required : :hidden] << field
        end
      end
    end
    result
  end

  def field_name(num)
    invalid! unless num.to_s.match?(/\A-?\d+\z/)
    number = num.to_i
    return ACTORS[number] if ACTORS.key?(number)

    option = @options[number.to_s]
    option.is_a?(Hash) ? OPTION_FIELDS.fetch([option['table'], option['field']], "field_#{number}") : "field_#{number}"
  end

  def predefined_value(field, value)
    if %w[name content].include?(field)
      invalid! unless value.is_a?(String) && value.length <= (field == 'name' ? 255 : 50_000)
      return JrcServiceDesk::Glpi::Normalize.text(value) if field == 'name'

      return JrcServiceDesk::Glpi::Content.rich(value, from_source: true)
    end
    number = JrcServiceDesk::Glpi::Identifiers.remote(value)
    range = case field
            when 'type' then 1..2
            when 'urgency', 'impact' then 1..5
            when 'priority', 'status' then 1..6
            else 0..9_223_372_036_854_775_807
            end
    invalid! unless range.include?(number)
    number
  end

  def build(template, source, type, category, profile)
    required = (%w[name content] + Array(template&.fetch(:required))).uniq.sort
    hidden = Array(template&.fetch(:hidden)).uniq.sort
    predefined = { 'type' => type, 'itilcategories_id' => category, 'urgency' => 3, 'impact' => 3, 'status' => 1 }
      .merge(template ? template[:predefined] : {})
    predefined['type'] = type if @type_supplied && type != 1 && !hidden.include?('type')
    predefined['itilcategories_id'] = category if category.positive? && !hidden.include?('itilcategories_id')
    validate_references!(predefined)
    unsupported = (required - FIELDS) + Array(template&.fetch(:unsupported))
    hidden.each do |field|
      unsupported << field if required.include?(field) && (self.class.missing?(predefined[field]) || field == 'content')
    end
    status_capability = STATUS_CAPABILITIES[predefined.fetch('status')]
    unsupported << 'status' if status_capability && !@access.context.capability?(status_capability)
    html = predefined['content'].is_a?(String) ? { 'content' => predefined['content'] } : {}
    predefined['content'] = JrcServiceDesk::Glpi::Normalize.text(predefined['content']) if predefined.key?('content')
    result = { entity_id: @entity, type: predefined.fetch('type'), category_id: predefined.fetch('itilcategories_id'),
      template_id: template&.fetch(:id), template_source: source, fields: FIELDS, required: required,
      hidden: hidden & FIELDS, predefined: predefined, predefined_html: html,
      supported: unsupported.empty?, unsupported_required: unsupported.uniq.sort }
    # Provenance does not make the same effective form a different policy.
    result[:version] = JrcServiceDesk::CanonicalJson.digest(result.except(:template_source).merge(
      connection_id: @access.connection.id, connection_version: @access.connection.lock_version,
      profile_id: JrcServiceDesk::Input.id(profile.fetch('id')), template_revision: template&.fetch(:revision)))
    result
  end

  def optional_id(value)
    return 0 if value.nil? || value == ''

    JrcServiceDesk::Glpi::Identifiers.remote(value)
  end

  def invalid!
    raise JrcServiceDesk::Glpi::Error.new('template_metadata_invalid')
  end
end
