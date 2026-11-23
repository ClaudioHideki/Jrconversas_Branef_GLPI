# frozen_string_literal: true

require_relative 'glpi_test_helper'
require_relative 'glpi_source_fixture'
require 'minitest/mock'

class GlpiSentimentSource < GlpiCommandSource
  attr_accessor :interactions
  attr_reader :searches

  def initialize
    super
    @searches = []
    rows['Ticket/101'].merge!('date' => '2026-09-30 12:00:00', 'date_mod' => '2026-10-20 12:00:00',
                              'content' => 'Outside period', 'users_id_recipient' => 77)
    @interactions = [
      { 'id' => 101, 'items_id' => 101, 'itemtype' => 'Ticket', 'users_id' => 77, 'is_private' => 0,
        'date_creation' => '2026-10-01 00:00:00', 'content' => '<p>Obrigado</p>' },
      { 'id' => 102, 'items_id' => 101, 'itemtype' => 'Ticket', 'users_id' => 900, 'is_private' => 1,
        'date_creation' => '2026-10-20 12:00:00', 'content' => 'Private, never send' },
      { 'id' => 103, 'items_id' => 101, 'itemtype' => 'Ticket', 'users_id' => 900, 'is_private' => 0,
        'date_creation' => '2026-11-01 00:00:00', 'content' => 'Outside exclusive end' }
    ]
  end

  def collection(path, parameters = {}, **_options)
    return rows.select { |key, _| key.start_with?('Ticket/') }.values.deep_dup if path == 'Ticket/'
    if path == 'search/Ticket/'
      @searches << parameters.deep_dup
      return rows.select { |key, _| key.start_with?('Ticket/') }.values.map { |row| { '2' => row.fetch('id') } }
    end
    return interactions.deep_dup if path == 'Ticket/101/ITILFollowup/'
    if path == 'Ticket/101/Ticket_User/'
      return [{ 'id' => 1, 'tickets_id' => 101, 'users_id' => 77, 'type' => 1 },
              { 'id' => 2, 'tickets_id' => 101, 'users_id' => 900, 'type' => 2 }]
    end

    super
  end

  def get(path, parameters = {})
    return { 'session' => { 'glpiID' => 900, 'glpiactiveentities' => [0] } } if path == 'getFullSession/'
    if path == 'listSearchOptions/Ticket/'
      return { '2' => { 'table' => 'glpi_tickets', 'field' => 'id' }, '15' => { 'table' => 'glpi_tickets', 'field' => 'date' },
               '19' => { 'table' => 'glpi_tickets', 'field' => 'date_mod' }, '80' => { 'table' => 'glpi_entities', 'field' => 'completename' } }
    end
    if path == 'search/Ticket/'
      @searches << parameters.deep_dup
      ids = rows.select { |key, _| key.start_with?('Ticket/') }.values.map { |row| row.fetch('id') }
      return { 'totalcount' => ids.size, 'data' => ids.empty? ? [] : [{ '2' => ids.max }] }
    end

    super
  end
end

class GlpiHistoricalSentimentTest < GlpiIntegrationTest
  def setup
    super
    @source = GlpiSentimentSource.new
    @analysis = JrcServiceDesk::Glpi::HistoricalSentiment.new(
      access: JrcServiceDesk::Glpi::Access.new(@identity), from: '2026-10-01', to: '2026-11-01'
    )
  end

  def test_candidates_include_older_tickets_with_interactions_but_exclude_other_entities_and_deleted
    @source.rows['Ticket/202'] = @source.rows['Ticket/101'].merge('id' => 202, 'entities_id' => 999)
    @source.rows['Ticket/303'] = @source.rows['Ticket/101'].merge('id' => 303, 'is_deleted' => 1)
    assert_equal [101], @analysis.candidates(client: @source).fetch(:ticket_ids)
    assert_includes @source.searches.first.fetch('criteria'),
                    { 'field' => 19, 'searchtype' => 'morethan', 'value' => '2026-09-30 23:59:59', 'link' => 'AND' }
    assert_equal 'DESC', @source.searches.first.fetch('order')
    assert_equal 'ASC', @source.searches.last.fetch('order')
    assert_includes @source.searches.last.fetch('criteria'), { 'field' => 2, 'searchtype' => 'lessthan', 'value' => 304, 'link' => 'AND' }
    assert_empty @source.writes
  end

  def test_public_period_projection_preserves_real_qualified_ids_and_excludes_private_notes_even_for_admin
    @source.interactions << @source.interactions.first.merge('id' => 104, 'users_id' => 900, 'content' => 'Technical response')
    @source.interactions << @source.interactions.first.except('is_private').merge('id' => 105, 'content' => 'Unconfirmed visibility')
    payloads = []
    client = Object.new
    client.define_singleton_method(:sentiment) do |payload|
      payloads << payload
      { 'model' => 'synthetic', 'report' => { 'evidence' => [{ 'message_id' => 'ITILFollowup/101' }] } }
    end
    metered = ->(**_arguments, &block) { block.call(nil, nil) }
    result = JrcNico::OperationalInference.stub(:metered, metered) do
      JrcNico::RuntimeClient.stub(:new, client) { @analysis.analyze(client: @source, ticket_id: 101) }
    end
    assert_equal [{ id: 'ITILFollowup/101', role: 'customer', content: 'Obrigado' },
                  { id: 'ITILFollowup/104', role: 'unknown', content: 'Technical response' }], payloads.first.fetch(:messages)
    assert_equal({ system: 'glpi', resource_type: 'Ticket', resource_id: '101' }, payloads.first.fetch(:source))
    assert_equal ['ITILFollowup/101', 'ITILFollowup/104'], result.fetch(:source_window).fetch(:references)
    assert result.fetch(:inferred)
    assert_empty @source.writes
  end

  def test_no_public_text_never_invokes_inference
    @source.interactions.first['is_private'] = 1
    JrcNico::OperationalInference.stub(:metered, ->(**) { flunk 'Inference must not run' }) do
      assert_equal 'no_public_text', @analysis.analyze(client: @source, ticket_id: 101).fetch(:status)
    end
    assert_empty @source.writes
  end

  def test_cross_entity_lookup_is_denied_before_inference
    @source.rows['Ticket/101']['entities_id'] = 999
    assert_raises(Pundit::NotAuthorizedError) { @analysis.analyze(client: @source, ticket_id: 101) }
    assert_empty @source.writes
  end

  def test_partial_month_uses_the_configured_source_timezone_in_search_criteria
    @connection.update!(timezone: 'America/Sao_Paulo')
    Time.stub(:current, Time.utc(2026, 11, 23, 15, 0, 0)) do
      analysis = JrcServiceDesk::Glpi::HistoricalSentiment.new(
        access: JrcServiceDesk::Glpi::Access.new(@identity), from: '2026-11-01', to: '2026-12-01'
      )
      result = analysis.candidates(client: @source)
      assert_equal '2026-11-23T12:00:00-03:00', result.fetch(:period).fetch(:to_exclusive)
      assert result.fetch(:period).fetch(:partial)
      assert_includes @source.searches.first.fetch('criteria'),
                      { 'field' => 15, 'searchtype' => 'lessthan', 'value' => '2026-11-23 12:00:00', 'link' => 'AND' }
    end
  end
end
