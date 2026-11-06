# frozen_string_literal: true

# Synthetic policy only: these weights are not Branef's production matrix.
require_relative 'intake_delivery_test_helper'

class IntakeClassificationIntegrationTest < IntakeDeliveryTest
  def test_distinct_impact_and_urgency_follow_the_published_matrix_not_the_declared_hint
    value = JrcServiceDesk::Intake::Classification.new(matrix).call(impact: 'one', urgency: 'blocked', declared_severity: 'critical')
    assert_equal 'classified', value.fetch('classification_state')
    assert_equal 3, value.fetch('classification_revision')
    assert_equal 'high', value.fetch('severity')
    assert_equal 2, value.fetch('impact_value')
    assert_equal 5, value.fetch('urgency_value')
  end

  def test_missing_or_unapproved_matrix_never_turns_a_hint_into_operational_criticality
    [nil, matrix.merge('approved' => false)].each do |policy|
      value = JrcServiceDesk::Intake::Classification.new(policy).call(impact: 'Synthetic affected scope', urgency: 'Synthetic deadline',
                                                                      declared_severity: 'critical')
      assert_equal 'awaiting_human', value.fetch('classification_state')
      assert_nil value.fetch('severity')
      assert_nil value.fetch('impact_value')
      assert_nil value.fetch('urgency_value')
    end
  end

  def test_matrix_requires_complete_unique_cells_and_bounded_native_values
    incomplete = matrix.deep_dup
    incomplete['cells'].pop
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Classification.new(incomplete) }
    invalid = matrix.deep_dup
    invalid['impacts'][0]['value'] = 99
    assert_raises(ArgumentError) { JrcServiceDesk::Intake::Classification.new(invalid) }
    classifier = JrcServiceDesk::Intake::Classification.new(matrix)
    assert_raises(ArgumentError) { classifier.call(impact: 'arbitrary', urgency: 'blocked') }
  end

  def test_normalization_derives_the_sla_from_matrix_criticality_and_keeps_the_hint_separate
    input = bug_input.merge('severity' => 'low', 'impact' => 'one', 'urgency' => 'blocked')
    normalized = JrcServiceDesk::Intake::Input.new(JrcServiceDesk::Intake::Catalogue.new(@catalogue), classification: matrix).call(input)
    assert_equal 'high', normalized.fetch('severity')
    assert_equal 'low', normalized.fetch('declared_severity')
    assert_equal({ 'duration' => 6, 'unit' => 'hours' }, normalized.fetch('sla'))
    assert_equal [2, 5], normalized.values_at('impact_value', 'urgency_value')
  end

  def test_unconfigured_matrix_records_human_triage_without_applying_a_speculative_sla
    normalized = JrcServiceDesk::Intake::Input.new(JrcServiceDesk::Intake::Catalogue.new(@catalogue)).call(
      bug_input.merge('impact' => 'Synthetic affected scope', 'urgency' => 'Synthetic urgency')
    )
    assert_equal 'awaiting_human', normalized.fetch('classification_state')
    assert normalized.fetch('classification_required')
    assert_nil normalized.fetch('severity')
    assert_equal({ 'unit' => 'none' }, normalized.fetch('sla'))
  end

  def test_immutable_configuration_accepts_a_versioned_matrix_without_granting_permissions
    values = @delivery_configuration.attributes.except('id', 'created_at', 'updated_at')
    values['revision'] = 3
    values['current'] = false
    values['mappings'] = @delivery_configuration.mappings.merge('classification' => matrix)
    record = JrcServiceDesk::IntakeConfiguration.create!(values)
    assert_equal 3, record.mappings.dig('classification', 'revision')
    assert_raises(ActiveRecord::RecordInvalid) { record.update!(mappings: record.mappings.except('classification')) }
    assert_equal 1, JrcServiceDesk::UnitMembership.where(account: @account).count
  end

  def test_unclassified_bug_never_opens_a_source_session_or_creates_a_command
    normalized = JrcServiceDesk::Intake::Input.new(JrcServiceDesk::Intake::Catalogue.new(@catalogue)).call(bug_input)
    @demand.update!(normalized_input: normalized)
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'Human classification must precede source access' }) do
      JrcServiceDesk::Intake::Delivery.new.call(demand_id: @demand.id)
    end
    assert_equal 'rejected', @demand.reload.state
    assert_equal 'intake_classification_required', @demand.error_code
    assert_empty @remote.writes
  end

  def test_mapping_keeps_the_two_native_axis_values_distinct
    normalized = JrcServiceDesk::Intake::Input.new(JrcServiceDesk::Intake::Catalogue.new(@catalogue), classification: matrix).call(
      bug_input.merge('impact' => 'one', 'urgency' => 'blocked')
    )
    @demand.update!(normalized_input: normalized)
    mappings = @delivery_configuration.mappings.deep_dup
    mappings['routes'][0].merge!(normalized.slice('reason', 'subject', 'severity'))
    values = @delivery_configuration.attributes.except('id', 'created_at', 'updated_at')
    replacement = JrcServiceDesk::IntakeConfiguration.create!(values.merge('revision' => 3, 'mappings' => mappings))
    @demand.update!(intake_configuration: replacement)
    attributes = JrcServiceDesk::Intake::Mapping.new(@demand).attributes
    assert_equal 2, attributes.fetch('impact')
    assert_equal 5, attributes.fetch('urgency')
  end

  private

  def bug_input
    @arguments.fetch('input').merge('reason' => 'bug', 'subject' => 'function', 'severity' => 'critical')
  end

  def matrix
    { 'revision' => 3, 'approved' => true,
      'impacts' => [{ 'code' => 'one', 'label' => 'Synthetic one user', 'value' => 2 },
                    { 'code' => 'many', 'label' => 'Synthetic several users', 'value' => 4 }],
      'urgencies' => [{ 'code' => 'routine', 'label' => 'Synthetic workaround', 'value' => 2 },
                      { 'code' => 'blocked', 'label' => 'Synthetic blocked operation', 'value' => 5 }],
      'cells' => [{ 'impact' => 'one', 'urgency' => 'routine', 'severity' => 'low' },
                  { 'impact' => 'one', 'urgency' => 'blocked', 'severity' => 'high' },
                  { 'impact' => 'many', 'urgency' => 'routine', 'severity' => 'medium' },
                  { 'impact' => 'many', 'urgency' => 'blocked', 'severity' => 'critical' }] }
  end
end
