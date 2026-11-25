# frozen_string_literal: true

require_relative 'glpi_test_helper'
require_relative 'glpi_source_fixture'
require 'minitest/mock'

class GlpiSentimentTimeoutTest < Minitest::Test
  def test_only_the_exact_sentiment_post_has_the_inference_budget
    refute(Rails.application.middleware.any? { |entry| entry.klass == JrcGlpiSentimentTimeout })
    captured = []
    middleware = JrcGlpiSentimentTimeout.new(lambda do |env|
      captured << env.fetch(Rack::Timeout::ENV_INFO_KEY).timeout
      [200, {}, []]
    end)
    path = '/api/v1/accounts/3/jrc_service_desk/glpi/tickets/4152/sentiment'
    middleware.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => path)
    middleware.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => path)
    middleware.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => "#{path}/other")
    middleware.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => path.sub('/tickets/4152', '/tickets/0'))
    ordinary = Rack::Timeout.new(->(_) {}).service_timeout
    assert_equal [100, ordinary, ordinary, ordinary], captured
  end
end

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

  def test_interactive_candidates_include_older_opening_dates_and_never_call_inference
    JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: @source)
    result = @analysis.candidate_page(filters: { 'page' => 1, 'per_page' => 25 })
    assert_equal [101], (result.fetch(:items).map { |row| row.fetch('id') })
    assert_equal 1, result.fetch(:meta).fetch(:total)
    assert_empty @source.writes
  end

  def test_batch_captures_every_authorized_candidate_and_prevents_duplicate_running_batches
    (201..226).each do |id|
      @source.rows["Ticket/#{id}"] = @source.rows.fetch('Ticket/101').merge('id' => id)
    end
    JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member, client: @source)
    service = JrcServiceDesk::Glpi::SentimentBatch.new
    access = JrcServiceDesk::Glpi::Access.new(@identity)
    filters = { 'from' => '2026-10-01', 'to' => '2026-11-01' }
    batch = service.prepare(access: access, values: filters)
    assert_equal 27, batch.total
    assert_equal [101] + (201..226).to_a, batch.items.order(:remote_id).pluck(:remote_id)
    assert_equal batch.id, service.latest(access: access).id
    assert_equal 27, service.rows(batch: batch, access: access, page: 1).fetch(:total)
    error = assert_raises(JrcServiceDesk::Glpi::Error) { service.prepare(access: access, values: filters) }
    assert_equal 'sentiment_batch_active', error.code

    first = batch.items.order(:id).first
    first.update!(state: 'running', updated_at: 20.minutes.ago)
    client = Object.new
    client.define_singleton_method(:session) { |read_only:, &block| raise unless read_only; block.call }
    result = ->(ticket_id:, **_options) { { ticket_id: ticket_id, status: 'no_public_text' } }
    analysis = Object.new
    analysis.define_singleton_method(:analyze, result)
    JrcServiceDesk::Glpi::HistoricalSentiment.stub(:new, analysis) do
      JrcServiceDesk::Glpi::Client.stub(:new, client) { service.step(batch) }
    end
    assert_equal 'interrupted', first.reload.error
    assert_equal({ 'failed' => 1, 'no_public_text' => 1, 'queued' => 25 }, batch.receipt.fetch(:counts))
    assert_equal 'cancelled', service.cancel(batch: batch).state
    assert_equal 25, batch.receipt.fetch(:counts).fetch('cancelled')
    assert_empty @source.writes
  end

  def test_candidates_include_older_tickets_with_interactions_but_exclude_other_entities_and_deleted
    @source.rows['Ticket/202'] = @source.rows['Ticket/101'].merge('id' => 202, 'entities_id' => 999)
    @source.rows['Ticket/303'] = @source.rows['Ticket/101'].merge('id' => 303, 'is_deleted' => 1)
    assert_equal [101], @analysis.candidates(client: @source).fetch(:ticket_ids)
    assert_includes @source.searches.first.fetch('criteria'),
                    { 'field' => 19, 'searchtype' => 'morethan', 'value' => '2026-09-30 23:59:59', 'link' => 'AND' }
    assert_equal 'DESC', @source.searches.first.fetch('order')
    assert_equal 'ASC', @source.searches.last.fetch('order')
    assert_includes @source.searches.last.fetch('criteria'), { 'field' => 2, 'searchtype' => 'contains', 'value' => '<=303', 'link' => 'AND' }
    assert_empty @source.writes
  end

  def test_public_period_projection_preserves_real_qualified_ids_and_excludes_private_notes_even_for_admin
    @source.interactions << @source.interactions.first.merge('id' => 104, 'users_id' => 900, 'content' => 'Technical response')
    @source.interactions << @source.interactions.first.except('is_private').merge('id' => 105, 'content' => 'Unconfirmed visibility')
    payloads = []
    client = Object.new
    client.define_singleton_method(:sentiment) do |payload|
      payloads << payload
      { 'model' => 'synthetic', 'usage' => { 'input_tokens' => 12, 'output_tokens' => 9, 'total_tokens' => 21 },
        'report' => { 'evidence' => [{ 'message_id' => 'ITILFollowup/101' }] } }
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
    assert_equal 21, result.fetch(:usage).fetch('total_tokens')
    assert_empty @source.writes
  end

  def test_selected_ticket_scope_needs_no_dates_and_includes_public_history_before_and_after_the_list_period
    analysis = JrcServiceDesk::Glpi::HistoricalSentiment.new(access: JrcServiceDesk::Glpi::Access.new(@identity), scope: 'ticket')
    payloads = []
    runtime = Object.new
    runtime.define_singleton_method(:sentiment) do |payload|
      payloads << payload
      { 'model' => 'synthetic-account-provider', 'usage' => { 'input_tokens' => 12, 'output_tokens' => 9, 'total_tokens' => 21 },
        'report' => { 'evidence' => [{ 'message_id' => 'Ticket/101' }] } }
    end
    result = JrcNico::OperationalInference.stub(:metered, ->(**_args, &block) { block.call(nil, nil) }) do
      JrcNico::RuntimeClient.stub(:new, runtime) { analysis.analyze(client: @source, ticket_id: 101) }
    end
    assert_equal %w[Ticket/101 ITILFollowup/101 ITILFollowup/103], payloads.first.fetch(:messages).pluck(:id)
    assert_equal 'ticket', result.fetch(:period).fetch(:scope)
    refute(payloads.first.fetch(:messages).any? { |row| row[:content].include?('Private') })
    assert_empty @source.writes
    assert_raises(ArgumentError) do
      JrcServiceDesk::Glpi::HistoricalSentiment.new(access: JrcServiceDesk::Glpi::Access.new(@identity), scope: 'ticket', from: '2026-10-01', to: '2026-11-01')
    end
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

  def test_a_window_that_loses_its_captured_ticket_never_reports_a_false_empty_history
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      @source.stub(:collection, []) { @analysis.candidates(client: @source) }
    end
    assert_equal 'source_changed', error.code
    assert_empty @source.writes
  end
end
