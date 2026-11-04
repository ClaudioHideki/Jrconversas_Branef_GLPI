# frozen_string_literal: true

class JrcServiceDesk::Glpi::TicketCreationPolicy
  def prepare!(access:, client:, command:)
    form = resolve(access, client, command)
    requested = command.template_policy['requested_version']
    changed! if requested && requested != form.fetch(:version)
    raise JrcServiceDesk::Glpi::Error.new('template_fields_unsupported', 422) unless form.fetch(:supported)

    defaults = form.fetch(:predefined).deep_dup
    defaults['name'] = JrcServiceDesk::Glpi::Content.plain(defaults['name']) if defaults.key?('name')
    defaults['content'] = form.fetch(:predefined_html).fetch('content') if defaults.key?('content')
    input = command.request_payload.deep_dup
    (form.fetch(:hidden) + %w[status]).uniq.each do |field|
      if input.key?(field) && !equivalent?(input[field], defaults[field])
        raise JrcServiceDesk::Glpi::Error.new('hidden_field_override', 422)
      end
      input[field] = defaults[field] if defaults.key?(field)
    end
    final = defaults.merge(input)
    if form.fetch(:required).any? { |field| missing?(final[field]) }
      raise JrcServiceDesk::Glpi::Error.new('required_fields_missing', 422)
    end
    if defaults.key?('content') && form.fetch(:required).include?('content') && equivalent?(final['content'], defaults['content'])
      raise JrcServiceDesk::Glpi::Error.new('required_content_unchanged', 422)
    end
    format = !input.key?('content') && defaults.key?('content') ? 'rich' : command.content_format
    contract = JrcServiceDesk::Glpi::CommandInput.new(operation: 'ticket.create', target_id: nil, entity_id: command.entity_id,
      attributes: final.merge('content_format' => format), prepared: true)
    @form.validate_references!(contract.input)
    payload = contract.input
    payload['_tickettemplate'] = form.fetch(:template_id) if form[:template_id]
    command.update!(request_payload: payload, content_format: format, template_version: form.fetch(:version),
      template_policy: command.template_policy.merge('template_id' => form[:template_id], 'version' => form.fetch(:version)))
  end

  def recheck!(access:, client:, command:)
    form = resolve(access, client, command)
    changed! unless form.fetch(:version) == command.template_version
    @form.validate_references!(command.request_payload)
  end

  private

  def resolve(access, client, command)
    @form = JrcServiceDesk::Glpi::TicketForm.new
    @form.call(access: access, client: client, filters: command.template_policy.fetch('selection'))
  end

  def equivalent?(one, two)
    return one == two unless one.is_a?(String) && two.is_a?(String)

    [one, two].map { |value| JrcServiceDesk::Glpi::Normalize.text(value).gsub(/[[:space:]]+/, ' ').strip }.uniq.length == 1
  end

  def missing?(value)
    value.nil? || value == 0 || value == false || (value.is_a?(String) && JrcServiceDesk::Glpi::Normalize.text(value).strip.empty?)
  end

  def changed!
    raise JrcServiceDesk::Glpi::Error.new('template_changed', 409)
  end
end
