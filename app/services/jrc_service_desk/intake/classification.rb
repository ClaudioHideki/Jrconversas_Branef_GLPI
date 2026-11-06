# frozen_string_literal: true

# Customer-approved weights are immutable configuration, never inferred from a visitor's hint.
class JrcServiceDesk::Intake::Classification
  def initialize(document)
    @document = document.nil? || document == {} ? nil : JSON.parse(JSON.generate(document))
    validate! if @document
  end

  def ready? = @document&.fetch('approved') == true

  def call(impact:, urgency:, declared_severity: nil)
    result = pending_result(impact, urgency, declared_severity)
    return result unless ready?

    cell = @document.fetch('cells').find { |row| row['impact'] == impact && row['urgency'] == urgency }
    raise ArgumentError, 'intake_classification_selection' unless cell

    result.merge('classification_state' => 'classified', 'severity' => cell.fetch('severity'),
                 'impact_value' => axis_value('impacts', impact), 'urgency_value' => axis_value('urgencies', urgency))
  end

  private

  def pending_result(impact, urgency, declared_severity)
    hint = declared_severity == '' ? nil : declared_severity
    allowed = hint.nil? || JrcServiceDesk::Intake::Catalogue::SEVERITIES.include?(hint)
    raise ArgumentError, 'intake_severity' unless allowed

    { 'classification_required' => true, 'classification_revision' => @document&.fetch('revision'),
      'declared_severity' => hint, 'impact' => bounded(impact), 'urgency' => bounded(urgency),
      'classification_state' => 'awaiting_human', 'severity' => nil, 'impact_value' => nil, 'urgency_value' => nil }
  end

  def bounded(value)
    return nil if value.nil? || value == ''
    raise ArgumentError, 'intake_classification_input' unless value.is_a?(String) && value.strip.length.between?(1, 1000) &&
                                                              value.index("\x00").nil?

    value.strip
  end

  def axis_value(axis, code) = @document.fetch(axis).find { |row| row['code'] == code }.fetch('value')

  def validate!
    keys!(@document, %w[revision approved impacts urgencies cells])
    raise ArgumentError, 'intake_classification_revision' unless @document['revision'].is_a?(Integer) && @document['revision'].positive?
    raise ArgumentError, 'intake_classification_approval' unless [true, false].include?(@document['approved'])

    %w[impacts urgencies].each { |axis| validate_axis!(@document.fetch(axis)) }
    validate_cells!
  end

  def validate_axis!(rows)
    rows!(rows, 1..5)
    raise ArgumentError, 'intake_classification_axis' unless rows.pluck('code').uniq.size == rows.size

    rows.each { |row| validate_axis_row!(row) }
  end

  def validate_axis_row!(row)
    keys!(row, %w[code label value])
    raise ArgumentError, 'intake_classification_axis' unless row['code'].is_a?(String) &&
                                                             JrcServiceDesk::Intake::Catalogue::CODE.match?(row['code'])
    raise ArgumentError, 'intake_classification_axis' unless row['value'].is_a?(Integer) && row['value'].between?(1, 5)

    validate_label!(row['label'])
  end

  def validate_label!(label)
    raise ArgumentError, 'intake_classification_label' unless label.is_a?(String) && label.strip.length.between?(1, 160) &&
                                                              !label.match?(/[\x00-\x1f]|\{\{|\}\}/)
  end

  def validate_cells!
    rows = @document.fetch('cells')
    pairs = @document.fetch('impacts').pluck('code').product(@document.fetch('urgencies').pluck('code'))
    rows!(rows, pairs.size..pairs.size)

    rows.each do |row|
      keys!(row, %w[impact urgency severity])
      raise ArgumentError, 'intake_classification_severity' unless JrcServiceDesk::Intake::Catalogue::SEVERITIES.include?(row['severity'])
    end
    raise ArgumentError, 'intake_classification_cells' unless rows.map { |row| row.values_at('impact', 'urgency') }.sort == pairs.sort
  end

  def rows!(rows, size)
    raise ArgumentError, 'intake_classification_rows' unless rows.is_a?(Array) && size.cover?(rows.size) && rows.all?(Hash)
  end

  def keys!(value, keys)
    raise ArgumentError, 'intake_classification_keys' unless value.is_a?(Hash) && value.keys.sort == keys.sort
  end
end
