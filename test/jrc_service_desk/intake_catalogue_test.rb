# frozen_string_literal: true

require 'minitest/autorun'
require 'json'

module JrcServiceDesk
end

module JrcServiceDesk::Intake; end

%w[catalogue classification input].each do |name|
  path = File.expand_path("../../app/services/jrc_service_desk/intake/#{name}.rb", __dir__)
  require path if File.exist?(path)
end

class IntakeCatalogueTest < Minitest::Test
  def setup
    @document = JSON.parse(File.read(File.join(__dir__, 'fixtures/intake_catalogue.json')))
  end

  def test_classifies_municipality_exception_without_cross_row_inference
    catalogue = JrcServiceDesk::Intake::Catalogue.new(@document)
    %w[north south].each do |location|
      result = catalogue.classify(system: 'example', location: location, reason: 'request', subject: 'access', profile: 'requester')
      assert_equal 'n2_n3', result['queue']
      assert_equal location == 'south' ? { 'duration' => 5, 'unit' => 'days' } : { 'duration' => 168, 'unit' => 'hours' }, result['sla']
    end
    assert_equal 'n1', catalogue.classify(system: 'example', location: 'south', reason: 'question', subject: 'access', profile: 'authority')['queue']
  end

  def test_rejects_unknown_combination_and_duplicate_or_unpublished_values
    catalogue = JrcServiceDesk::Intake::Catalogue.new(@document)
    assert_raises(ArgumentError) do
      catalogue.classify(system: 'other', location: 'south', reason: 'request', subject: 'access', profile: 'requester')
    end
    assert_raises(ArgumentError) do
      catalogue.classify(system: 'example', location: 'south', reason: 'question', subject: 'function', profile: 'requester')
    end
    @document['systems'][0]['reasons'][1]['sla_overrides'] << @document['systems'][0]['reasons'][1]['sla_overrides'][0].dup
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Catalogue.new(@document) }
  end

  def test_preserves_days_and_no_deadline
    catalogue = JrcServiceDesk::Intake::Catalogue.new(@document)
    result = catalogue.classify(system: 'example', location: 'south', reason: 'improvement', subject: 'other', profile: 'requester')
    assert_equal({ 'unit' => 'none' }, result['sla'])
    assert_nil result['severity']
    assert_raises(ArgumentError) do
      catalogue.classify(system: 'example', location: 'south', reason: 'bug', subject: 'function', profile: 'requester')
    end
    result = catalogue.classify(system: 'example', location: 'south', reason: 'bug', subject: 'function',
                                profile: 'requester', severity: 'critical')
    assert_equal({ 'duration' => 6, 'unit' => 'hours' }, result['sla'])
  end

  def test_declared_profile_does_not_authorize_lookup_or_choose_remote_identity
    catalogue = JrcServiceDesk::Intake::Catalogue.new(@document)
    input = { 'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
              'profile' => 'authority', 'identifier' => '123.456.789-01', 'email' => ' request@example.invalid ',
              'description' => 'Synthetic access request' }
    result = JrcServiceDesk::Intake::Input.new(catalogue).call(input)
    assert_equal '12345678901', result['identifier']
    assert_equal 'cpf', result['identifier_type']
    assert_equal 'request@example.invalid', result['email']
    assert_nil result['remote_id']
    assert_nil result['authenticated']
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Input.new(catalogue).call(input.merge('entity_id' => 0)) }
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Input.new(catalogue).call(input.merge('email' => "a@example.invalid\nb@example.invalid")) }
  end

  def test_catalogue_is_a_snapshot_and_does_not_expose_mutable_internals
    catalogue = JrcServiceDesk::Intake::Catalogue.new(@document)
    @document['systems'].clear
    result = catalogue.classify(system: 'example', location: 'south', reason: 'question', subject: 'access', profile: 'requester')
    result['sla']['duration'] = 1
    assert_equal 24,
                 catalogue.classify(system: 'example', location: 'south', reason: 'question', subject: 'access', profile: 'requester').dig('sla',
                                                                                                                                           'duration')
    assert_equal 4, catalogue.route_count
  end
end
