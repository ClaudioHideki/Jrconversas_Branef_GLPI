# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'active_support/core_ext/numeric/bytes'
require 'logger'

module JrcServiceDesk
  module Glpi; end
end

module Rails
  def self.logger
    @logger ||= Logger.new(IO::NULL)
  end
end

require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/glpi/client'

class GlpiTransportTest < Minitest::Test
  Response = Struct.new(:code, :payload, :headers) do
    def [](key)
      headers[key.downcase]
    end

    def read_body
      yield(code == '204' ? '' : JSON.generate(payload))
    end
  end

  def setup
    connection = Struct.new(:base_url, :user_token, :app_token).new(
      'https://glpi.example.invalid/apirest.php', 'synthetic-user', 'synthetic-app')
    @client = JrcServiceDesk::Glpi::Client.new(connection)
    @responses = []
    @requests = []
    @transport = lambda do |url, **options, &block|
      @requests << { url: url, body: options[:body], headers: options[:headers] }
      response = @responses.shift || raise('Unexpected extra HTTP request')
      block.call(response)
    end
  end

  def test_collection_reads_beyond_first_two_hundred_items
    @responses = [Response.new('206', (1..200).map { |id| { 'id' => id } }, { 'content-range' => '0-199/205' }),
                  Response.new('206', (201..205).map { |id| { 'id' => id } }, { 'content-range' => '200-204/205' })]
    SsrfFilter.stub(:get, @transport) do
      rows = @client.collection('Ticket/101/ITILFollowup/').to_a
      assert_equal 205, rows.size
      assert_equal 205, rows.last['id']
      assert_equal %w[0-199 200-399], @requests.map { |r| URI.decode_www_form(URI(r[:url]).query).to_h.fetch('range') }
    end
  end

  def test_collection_propagates_access_denial_on_a_later_page
    @responses = [Response.new('206', [{ 'id' => 1 }], { 'content-range' => '0-0/2' }),
                  Response.new('403', ['ERROR_RIGHT_MISSING', 'Denied'], {})]
    SsrfFilter.stub(:get, @transport) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { @client.collection('TicketTask/', batch_size: 1).to_a }
      assert_equal 'ERROR_RIGHT_MISSING', error.code
      assert_equal 403, error.http_status
    end
  end

  def test_collection_rejects_a_repeated_page_instead_of_looping_or_duplicating
    @responses = [Response.new('206', [{ 'id' => 1 }], { 'content-range' => '0-0/2' }),
                  Response.new('206', [{ 'id' => 1 }], { 'content-range' => '0-0/2' })]
    SsrfFilter.stub(:get, @transport) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { @client.collection('TicketTask/', batch_size: 1).to_a }
      assert_equal 'source_changed', error.code
    end
  end

  def test_collection_accepts_a_legitimate_empty_search_without_data
    @responses = [Response.new('200', { 'totalcount' => 0 }, {})]
    SsrfFilter.stub(:get, @transport) do
      assert_empty @client.collection('search/Ticket/').to_a
    end
  end

  def test_collection_rejects_missing_data_for_a_positive_count
    @responses = [Response.new('200', { 'totalcount' => 2 }, {})]
    SsrfFilter.stub(:get, @transport) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { @client.collection('search/Ticket/').to_a }
      assert_equal 'invalid_response', error.code
    end
  end

  def test_collection_rejects_an_empty_page_before_the_reported_total
    @responses = [Response.new('206', [], { 'content-range' => '0-0/2' })]
    SsrfFilter.stub(:get, @transport) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { @client.collection('TicketTask/').to_a }
      assert_equal 'source_changed', error.code
    end
  end

  def test_last_response_exposes_only_non_secret_pagination_metadata
    @responses = [Response.new('206', [], { 'content-range' => '0-0/0', 'accept-range' => 'Ticket 1000',
                                           'authorization' => 'MUST_NOT_LEAK' })]
    SsrfFilter.stub(:get, @transport) do
      @client.get('Ticket/')
      assert_equal({ status: 206, content_range: '0-0/0', accept_range: 'Ticket 1000' }, @client.last_response)
    end
  end

  def test_absolute_urls_and_path_traversal_never_reach_transport
    SsrfFilter.stub(:get, @transport) do
      ['https://other.example.invalid/Ticket/', '../Ticket/', 'Ticket/1?alt=media'].each do |path|
        assert_raises(ArgumentError) { @client.get(path) }
      end
      assert_empty @requests
    end
  end

  def test_typed_update_sends_only_the_requested_item_and_fields
    @responses = [Response.new('200', [{ '101' => true }], {})]
    SsrfFilter.stub(:patch, @transport) do
      @client.update_item('Ticket', 101, { 'priority' => 4 })
      assert_equal 'https://glpi.example.invalid/apirest.php/Ticket/101', @requests.first[:url]
      assert_equal({ 'input' => { 'id' => 101, 'priority' => 4 } }, JSON.parse(@requests.first[:body]))
    end
  end

  def test_typed_create_preserves_existing_ticket_contract
    @responses = [Response.new('201', { 'id' => 102 }, {})]
    SsrfFilter.stub(:post, @transport) do
      assert_equal({ 'id' => 102 }, @client.create_ticket({ 'name' => 'Synthetic ticket' }))
      assert_equal({ 'input' => { 'name' => 'Synthetic ticket' } }, JSON.parse(@requests.first[:body]))
    end
  end

  def test_delete_defaults_to_recoverable_deletion
    @responses = [Response.new('200', [{ '101' => true }], {})]
    SsrfFilter.stub(:delete, @transport) do
      @client.delete_item('Ticket', 101)
      assert_equal({ 'input' => { 'id' => 101 }, 'force_purge' => false }, JSON.parse(@requests.first[:body]))
    end
  end

  def test_mutation_does_not_allow_global_user_or_profile_administration
    assert_raises(ArgumentError) { @client.create_item('Profile', { 'name' => 'Privileged' }) }
    assert_raises(ArgumentError) { @client.update_item('User', 1, { 'name' => 'Changed' }) }
  end

  def test_single_deletion_accepts_documented_no_content_acknowledgement
    @responses = [Response.new('204', nil, {})]
    SsrfFilter.stub(:delete, @transport) do
      assert_equal({ 'id' => 101, 'deleted' => true }, @client.delete_item('Ticket', 101))
    end
  end

  def test_multistatus_preserves_per_item_results_for_the_command_executor
    @responses = [Response.new('207', [{ '101' => false, 'message' => 'Denied' }], {})]
    SsrfFilter.stub(:patch, @transport) do
      assert_equal([{ '101' => false, 'message' => 'Denied' }], @client.update_item('Ticket', 101, { 'priority' => 4 }))
    end
  end

  def test_collection_rejects_partial_response_without_count_or_range
    @responses = [Response.new('206', [{ 'id' => 1 }], {})]
    SsrfFilter.stub(:get, @transport) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { @client.collection('TicketTask/').to_a }
      assert_equal 'invalid_response', error.code
    end
  end

  def test_collection_continues_a_short_partial_page_with_unknown_total
    @responses = [Response.new('206', [{ 'id' => 1 }], { 'content-range' => '0-0/*' }),
                  Response.new('206', [{ 'id' => 2 }], { 'content-range' => '1-1/2' })]
    SsrfFilter.stub(:get, @transport) do
      assert_equal [1, 2], @client.collection('TicketTask/').map { |row| row['id'] }
    end
  end

  def test_existing_ticket_creation_does_not_return_multistatus_as_a_single_ticket
    @responses = [Response.new('207', [{ 'id' => false, 'message' => 'Denied' }], {})]
    SsrfFilter.stub(:post, @transport) do
      error = assert_raises(JrcServiceDesk::Glpi::Error) { @client.create_ticket({ 'name' => 'Synthetic' }) }
      assert_equal 'invalid_response', error.code
    end
  end
end
