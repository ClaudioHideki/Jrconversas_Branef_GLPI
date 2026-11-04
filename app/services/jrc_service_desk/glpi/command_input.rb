# frozen_string_literal: true

require 'cgi'

class JrcServiceDesk::Glpi::CommandInput
  attr_reader :operation, :descriptor, :target_id, :parent_id, :entity_id, :input, :expected_version, :reason, :content_format, :template_id

  def initialize(operation:, target_id:, entity_id:, attributes:, expected_version: nil, reason: nil, prepared: false, partial: false)
    @operation = operation
    raise ArgumentError if partial && operation != 'ticket.create'
    @partial = partial
    @descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch(operation)
    @entity_id = JrcServiceDesk::Glpi::Identifiers.remote(entity_id)
    @target_id = target_id.nil? ? nil : JrcServiceDesk::Input.id(target_id)
    raise ArgumentError unless (descriptor[:verb] == 'post') == @target_id.nil?
    raise ArgumentError unless expected_version.nil? || (expected_version.is_a?(String) && expected_version.length.between?(1, 100))
    if expected_version && descriptor[:verb] == 'post' && !descriptor[:parent]
      raise ArgumentError, 'Creation without a parent does not support an expected version'
    end
    raise ArgumentError unless reason.nil? || (reason.is_a?(String) && reason.strip.length.between?(1, 2000))
    raise ArgumentError, 'Deletion requires a reason' if descriptor[:admin] && descriptor[:verb] == 'delete' && reason.blank?

    @expected_version = expected_version
    @reason = reason
    allowed = descriptor[:fields] + %w[content_format] + (descriptor[:parent] ? %w[parent_id] : [])
    values = JrcServiceDesk::Input.attributes(attributes, allowed)
    if operation == 'ticket.create'
      selected = values.delete('template_id')
      @template_id = JrcServiceDesk::Glpi::Identifiers.remote(selected) unless selected.nil? || selected == ''
      @template_id = nil if @template_id == 0
    end
    explicit_format = values.key?('content_format')
    @content_format = values.delete('content_format') || 'plain'
    raise ArgumentError unless %w[plain rich].include?(content_format)
    if explicit_format && (values.keys & %w[content answer]).empty?
      raise ArgumentError, 'Content format requires content or answer'
    end
    @parent_id = JrcServiceDesk::Input.id(values.delete('parent_id')) if descriptor[:parent]
    raise ArgumentError, 'Required fields missing' unless partial || (descriptor[:required] - values.keys).empty?

    @input = values.dup
    input.each do |field, value|
      input[field] = normalize(field, value, prepared)
    end
    if descriptor[:verb] == 'patch' && input.empty? && descriptor[:defaults].empty?
      raise ArgumentError, 'No changes requested'
    end
    input.merge!(descriptor[:defaults])
    if descriptor[:parent]
      input[descriptor.fetch(:parent_field)] = parent_id
    elsif descriptor[:verb] == 'post'
      if descriptor[:type] == 'KnowbaseItem'
        input['_visibility'] = { '_type' => 'Entity', 'entities_id' => @entity_id, 'is_recursive' => 0 }
      else
        raise ArgumentError if input.key?('entities_id') && input['entities_id'] != @entity_id

        input['entities_id'] = @entity_id
      end
    end
    if input['begin'] || input['end']
      if descriptor[:verb] == 'post' || (input['begin'] && input['end'])
        raise ArgumentError unless input['begin'] && input['end'] && input['begin'] < input['end']
      end
    end
  end

  def fingerprint(connection_version)
    values = { operation: operation, type: descriptor[:type], target_id: target_id,
      parent_id: parent_id, entity_id: entity_id, input: input, expected_version: expected_version,
      reason: reason, content_format: content_format, connection_version: connection_version }
    values[:template_id] = template_id if template_id
    JrcServiceDesk::CanonicalJson.digest(values)
  end

  private

  def normalize(field, value, prepared)
    if %w[name content answer comment comment_submission comment_validation value].include?(field)
      return '' if @partial && %w[name content].include?(field) && value.is_a?(String) && value.strip.empty?
      maximum = field == 'name' ? 255 : 50_000
      raise ArgumentError unless value.is_a?(String) && value.strip.length.between?(1, maximum)

      return value if prepared
      if %w[content answer].include?(field) && content_format == 'rich'
        sanitized = JrcServiceDesk::Glpi::Content.rich(value.strip)
        raise ArgumentError if sanitized.strip.empty?

        return sanitized
      end
      return JrcServiceDesk::Glpi::Content.plain(value.strip)
    end
    if %w[begin end begin_date end_date].include?(field)
      raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)

      DateTime.strptime(value, '%Y-%m-%d %H:%M:%S')
      return value
    end
    if field == 'itemtype'
      raise ArgumentError unless JrcServiceDesk::Glpi::ResourceQuery::ASSET_TYPES.include?(value)

      return value
    end
    number = JrcServiceDesk::Glpi::Identifiers.remote(value)
    range = case field
            when 'urgency', 'impact' then 1..5
            when 'priority' then 1..6
            when 'type' then 1..(descriptor[:type] == 'Ticket' ? 2 : 3)
            when 'status'
              if descriptor[:type].end_with?('Validation')
                3..4
              elsif descriptor[:type] == 'Change'
                [1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
              elsif descriptor[:type] == 'Problem'
                1..8
              else
                1..6
              end
            when 'state' then 0..2
            when 'is_private', 'is_faq', 'is_recursive', 'is_incident', 'is_request', 'is_problem', 'is_change' then 0..1
            when 'actiontime' then 0..31_536_000
            else 0..9_223_372_036_854_775_807
            end
    raise ArgumentError unless range.include?(number)

    number
  end
end
