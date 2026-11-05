# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'active_support/all'
require 'action_view'

module JrcServiceDesk
  module Glpi; end
end

require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/glpi/normalize'
require_relative '../../app/services/jrc_service_desk/glpi/ticket_query'

class GlpiTicketQueryTest < Minitest::Test
  class Access
    def ready! = self
    def entity_ids = [0]
    def all_tickets? = true
    def glpi_user_id = 55
  end

  class Source
    attr_accessor :duplicate, :changed

    def get(path, parameters)
      raise 'Wrong source route' unless path == 'search/Ticket/'

      first, last = parameters.fetch('range').split('-').map(&:to_i)
      rows = (first...[last + 1, 10_205].min).map { |index| { '2' => duplicate && index == 201 ? 1 : index + 1 } }
      { 'data' => rows, 'totalcount' => changed && first.positive? ? 10_206 : 10_205 }
    end
  end

  def test_complete_query_reads_10205_records_without_functional_cap
    rows = JrcServiceDesk::Glpi::TicketQuery.new(Access.new, {}).all(Source.new)
    assert_equal 10_205, rows.size
    assert_equal 10_205, rows.last.fetch('id')
  rescue JrcServiceDesk::Glpi::Error => error
    flunk "Complete authorized query was refused: #{error.code}"
  end

  def test_pagination_detects_duplicate_ids_and_changed_source_count
    %i[duplicate changed].each do |fault|
      source = Source.new
      source.public_send("#{fault}=", true)
      error = assert_raises(JrcServiceDesk::Glpi::Error) { JrcServiceDesk::Glpi::TicketQuery.new(Access.new, {}).all(source) }
      assert_equal 'source_changed', error.code
    end
  end

  def test_numeric_search_matches_ticket_number_or_title
    criteria = JrcServiceDesk::Glpi::TicketQuery.new(Access.new, { 'search' => '10205' }).parameters(offset: 0, size: 100).fetch('criteria')
    assert_includes criteria, { 'link' => 'AND', 'criteria' => [
      { 'field' => 1, 'searchtype' => 'contains', 'value' => '10205', 'link' => 'AND' },
      { 'field' => 2, 'searchtype' => 'equals', 'value' => 10_205, 'link' => 'OR' }
    ] }
    criteria = JrcServiceDesk::Glpi::TicketQuery.new(Access.new, { 'search' => 'Reference 10205' }).parameters(offset: 0, size: 100).fetch('criteria')
    assert_includes criteria, { 'field' => 1, 'searchtype' => 'contains', 'value' => 'Reference 10205', 'link' => 'AND' }
  end
end
