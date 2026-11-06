# frozen_string_literal: true

require 'json'

# Published business codes are not remote IDs or permission grants.
class JrcServiceDesk::Intake::Catalogue
  SCHEMA = 'jrc-service-desk-intake/1'
  SEVERITIES = %w[low medium high critical].freeze
  QUEUES = %w[n1 n2 n3 n2_n3 management].freeze
  CODE = /\A[a-z][a-z0-9_]{0,63}\z/

  def initialize(document)
    @document = JSON.parse(JSON.generate(document))
    keys!(@document, %w[schema revision systems])
    raise ArgumentError, 'intake_catalogue_version' unless @document['schema'] == SCHEMA &&
                                                           @document['revision'].is_a?(Integer) && @document['revision'].positive?

    rows!(@document['systems'], 25).each { |system| validate_system!(system) }
  end

  def revision = @document.fetch('revision')

  def document = copy(@document)

  def route_count
    @document.fetch('systems').sum { |system| system.fetch('reasons').sum { |reason| reason.fetch('subjects').size } }
  end

  def classify(system:, location:, reason:, subject:, **options)
    raise ArgumentError, 'intake_selection' unless (options.keys - %i[profile severity]).empty?

    system_row = find!(@document.fetch('systems'), system)
    find!(system_row.fetch('locations'), location)
    validate_profile!(system_row.fetch('profiles'), options[:profile])
    reason_row = find!(system_row.fetch('reasons'), reason)
    subject_row = find!(reason_row.fetch('subjects'), subject)
    copy('system' => system, 'location' => location, 'reason' => reason, 'subject' => subject,
         'profile' => blank_to_nil(options[:profile]), 'severity' => blank_to_nil(options[:severity]),
         'queue' => reason_row.fetch('queue'), 'sla' => sla_for(reason_row, location, options[:severity]),
         'revision' => revision, 'subject_label' => subject_row.fetch('label'))
  end

  private

  def blank_to_nil(value) = value == '' ? nil : value

  def validate_profile!(profiles, value)
    return find!(profiles, value) unless profiles.empty?
    raise ArgumentError, 'intake_profile' unless blank_to_nil(value).nil?
  end

  def sla_for(reason_row, location, severity)
    override = reason_row.fetch('sla_overrides', []).find { |row| row['location'] == location }
    sla = (override || reason_row).fetch('sla')
    if sla.key?('by_severity')
      raise ArgumentError, 'intake_severity' unless SEVERITIES.include?(severity)

      sla.fetch('by_severity').fetch(severity)
    else
      raise ArgumentError, 'intake_unexpected_severity' unless blank_to_nil(severity).nil?

      sla
    end
  end

  def validate_system!(system)
    keys!(system, %w[code label locations profiles reasons])
    named!(system)
    named_rows!(system['locations'], 100)
    named_rows!(system['profiles'], 20, empty: true)
    rows!(system['reasons'], 20).each { |reason| validate_reason!(reason, system) }
  end

  def validate_reason!(reason, system)
    keys!(reason, %w[code label queue subjects sla], optional: %w[sla_overrides])
    named!(reason)
    raise ArgumentError, 'intake_queue' unless QUEUES.include?(reason['queue'])

    named_rows!(reason['subjects'], 100)
    validate_sla!(reason['sla'])
    validate_overrides!(reason.fetch('sla_overrides', []), reason, system)
  end

  def validate_overrides!(overrides, reason, system)
    raise ArgumentError, 'intake_sla_overrides' unless overrides.is_a?(Array) && overrides.size <= 100 && overrides.all?(Hash)

    unique!(overrides, 'location')
    overrides.each do |row|
      keys!(row, %w[location sla])
      find!(system.fetch('locations'), row['location'])
      validate_sla!(row['sla'])
      raise ArgumentError, 'intake_severity_shape' unless row['sla'].key?('by_severity') == reason['sla'].key?('by_severity')
    end
  end

  def validate_sla!(sla)
    raise ArgumentError, 'intake_sla' unless sla.is_a?(Hash)

    if sla.key?('by_severity')
      keys!(sla, %w[by_severity])
      keys!(sla['by_severity'], SEVERITIES)
      sla['by_severity'].each_value { |value| validate_duration!(value) }
    else
      validate_duration!(sla)
    end
  end

  def validate_duration!(value)
    if value.is_a?(Hash) && value['unit'] == 'none'
      keys!(value, %w[unit])
      return
    end
    keys!(value, %w[duration unit])
    raise ArgumentError, 'intake_duration' unless value['duration'].is_a?(Integer) && value['duration'].between?(1, 8760) &&
                                                  %w[hours days].include?(value['unit'])
  end

  def named!(row)
    raise ArgumentError, 'intake_code' unless row['code'].is_a?(String) && CODE.match?(row['code'])

    label = row['label']
    raise ArgumentError, 'intake_label' unless label.is_a?(String) && label.strip.length.between?(1, 160) &&
                                               !label.match?(/[\x00-\x1f]|\{\{|\}\}/)
  end

  def rows!(rows, maximum, empty: false)
    raise ArgumentError, 'intake_rows' unless rows.is_a?(Array) && rows.all?(Hash)
    raise ArgumentError, 'intake_rows' unless rows.size.between?(empty ? 0 : 1, maximum)

    unique!(rows, 'code')
    rows
  end

  def unique!(rows, field)
    raise ArgumentError, 'intake_duplicate' unless rows.map { |row| row.fetch(field, nil) }.uniq.size == rows.size
  end

  def named_rows!(rows, maximum, empty: false)
    rows!(rows, maximum, empty: empty).each do |row|
      keys!(row, %w[code label])
      named!(row)
    end
  end

  def keys!(value, required, optional: [])
    raise ArgumentError, 'intake_keys' unless value.is_a?(Hash) && (required - value.keys).empty? &&
                                              (value.keys - required - optional).empty?
  end

  def find!(rows, code)
    rows.find { |row| row['code'] == code } || raise(ArgumentError, 'intake_unknown_code')
  end

  def copy(value) = JSON.parse(JSON.generate(value))
end
