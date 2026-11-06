# frozen_string_literal: true

class JrcServiceDesk::Intake::Input
  FIELDS = %w[system location reason subject profile severity impact urgency identifier email description].freeze

  def initialize(catalogue, classification: nil)
    @catalogue = catalogue
    @classification = JrcServiceDesk::Intake::Classification.new(classification)
  end

  def call(attributes)
    raise ArgumentError, 'intake_input' unless attributes.is_a?(Hash) && (attributes.keys - FIELDS).empty?

    classification = classify(attributes)
    selection = @catalogue.classify(
      system: attributes.fetch('system'), location: attributes.fetch('location'),
      reason: attributes.fetch('reason'), subject: attributes.fetch('subject'),
      profile: attributes['profile'], severity: classification['severity'],
      classification_pending: classification['classification_state'] == 'awaiting_human'
    ).merge(classification)
    identifier = normalize_identifier(attributes.fetch('identifier'))
    selection.merge('identifier' => identifier, 'identifier_type' => identifier.length == 11 ? 'cpf' : 'cnpj',
                    'email' => normalize_email(attributes.fetch('email')), 'description' => normalize_description(attributes.fetch('description')))
  rescue KeyError
    raise ArgumentError, 'intake_required_field'
  end

  private

  def classify(attributes)
    unless @catalogue.classification_required?(attributes.fetch('system'), attributes.fetch('reason'))
      unexpected = attributes.values_at('severity', 'impact', 'urgency').any? { |value| !value.nil? && value != '' }
      raise ArgumentError, 'intake_unexpected_severity' if unexpected

      return { 'classification_required' => false, 'classification_state' => 'not_required', 'severity' => nil }
    end

    @classification.call(impact: attributes['impact'], urgency: attributes['urgency'], declared_severity: attributes['severity'])
  end

  def normalize_identifier(value)
    raise ArgumentError, 'intake_identifier' unless value.is_a?(String) && value.length <= 30

    value = value.gsub(%r{[.\-/\s]}, '')
    raise ArgumentError, 'intake_identifier' unless value.match?(/\A(?:[0-9]{11}|[0-9]{14})\z/)

    value
  end

  def normalize_email(value)
    raise ArgumentError, 'intake_email' unless value.is_a?(String) && value.length <= 254 && !value.match?(/[\r\n\x00]/)

    value = value.strip
    raise ArgumentError, 'intake_email' unless value.match?(/\A[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+\z/)

    value
  end

  def normalize_description(value)
    raise ArgumentError, 'intake_description' unless value.is_a?(String) && value.strip.length.between?(1, 5000) &&
                                                     value.index("\x00").nil?

    value.strip
  end
end
