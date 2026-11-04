# frozen_string_literal: true

class JrcServiceDesk::Glpi::Collection
  def initialize(client, path, parameters = {}, batch_size: 200)
    raise ArgumentError unless batch_size.is_a?(Integer) && batch_size.between?(1, 1000)

    @client = client
    @path = path
    @parameters = parameters
    @batch_size = batch_size
  end

  def each
    return enum_for(:each) unless block_given?

    offset = 0
    expected = nil
    seen = {}
    loop do
      data = @client.get(@path, @parameters.merge('range' => "#{offset}-#{offset + @batch_size - 1}"))
      rows, total = page(data, offset)
      source_changed! if expected && total && expected != total
      expected ||= total
      source_changed! if rows.empty? && expected && offset < expected
      partial = @client.last_response&.fetch(:status, nil) == 206
      source_changed! if rows.empty? && partial && expected.nil?

      rows.each do |row|
        raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless row.is_a?(Hash)

        id = row.key?('id') ? row['id'] : row['2']
        raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless id.to_s.match?(/\A\d+\z/)
        source_changed! if seen[id.to_s]

        seen[id.to_s] = true
      end
      rows.each { |row| yield row }
      offset += rows.size
      source_changed! if expected && offset > expected
      break if expected ? offset == expected : !partial && rows.size < @batch_size
    end
  end

  private

  def page(data, offset)
    if data.is_a?(Array)
      rows = data
      total = nil
    elsif data.is_a?(Hash)
      total = count(data.fetch('totalcount'))
      rows = data.fetch('data') do
        raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless total.zero?

        []
      end
      rows = rows.values if rows.is_a?(Hash)
    else
      raise JrcServiceDesk::Glpi::Error.new('invalid_response')
    end
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless rows.is_a?(Array)

    range = @client.last_response&.fetch(:content_range, nil)
    if @client.last_response&.fetch(:status, nil) == 206 && range.nil? && total.nil?
      raise JrcServiceDesk::Glpi::Error.new('invalid_response')
    end
    if range
      match = /\A(\d+)-(\d+)\/(\d+|\*)\z/.match(range)
      raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless match

      header_total = match[3] == '*' ? nil : count(match[3])
      source_changed! if total && header_total && total != header_total
      total ||= header_total
      source_changed! unless match[1].to_i == offset || total == 0
      source_changed! if rows.any? && match[2].to_i - match[1].to_i + 1 != rows.size
    end
    [rows, total]
  rescue KeyError
    raise JrcServiceDesk::Glpi::Error.new('invalid_response'), cause: nil
  end

  def count(value)
    raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless value.to_s.match?(/\A\d+\z/)

    value.to_i
  end

  def source_changed!
    raise JrcServiceDesk::Glpi::Error.new('source_changed', 409)
  end
end
