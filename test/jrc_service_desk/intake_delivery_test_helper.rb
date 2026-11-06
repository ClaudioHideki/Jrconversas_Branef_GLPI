# frozen_string_literal: true

# Shared flat synthetic delivery setup; the same real executor is used by lifecycle tests.
# rubocop:disable Metrics/MethodLength
require_relative 'intake_test_helper'
require_relative 'intake_source_fixture'

class IntakeDeliveryTest < IntakeIntegrationTest
  def setup
    super
    @connection.update!(primary_source: true)
    JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
    @remote = IntakeGlpiSource.new
    @remote.rows.merge!(
      'User/77' => { 'id' => 77, 'name' => 'Synthetic requester', 'is_active' => 1 },
      'Group/20' => { 'id' => 20, 'name' => 'Synthetic N2/N3', 'entities_id' => 0, 'is_recursive' => 1, 'is_assign' => 1 },
      'ITILCategory/10' => { 'id' => 10, 'name' => 'Synthetic access', 'entities_id' => 0, 'is_recursive' => 1,
                             'is_request' => 1, 'is_incident' => 1, 'tickettemplates_id_demand' => 0, 'tickettemplates_id_incident' => 0 },
      'SLA/30' => { 'id' => 30, 'name' => 'Synthetic five days', 'entities_id' => 0, 'slms_id' => 40,
                    'type' => 0, 'number_time' => 5, 'definition_time' => 'day', 'calendars_id' => 0 },
      'SLM/40' => { 'id' => 40, 'name' => 'Synthetic agreement', 'entities_id' => 0, 'is_recursive' => 1,
                    'calendars_id' => 0, 'use_ticket_calendar' => 0 }
    )
    @delivery_configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 2, catalogue: @catalogue,
      mode: 'on_qualification', enabled: true, remote_writes_enabled: true, responses: intake_responses,
      mappings: { 'routes' => [{ 'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
                                 'profile' => 'requester', 'severity' => nil, 'entity_id' => 0, 'category_id' => 10, 'group_id' => 20,
                                 'requester_policy' => 'mapped_contact', 'sla' => { 'id' => 30, 'purpose' => 'resolve', 'calendar_id' => 0 } }],
                  'requesters' => [{ 'contact_id' => @conversation.contact_id, 'entity_id' => 0, 'user_id' => 77 }],
                  'notifications' => intake_notifications }
    )
    args = @arguments.merge('configuration_id' => @delivery_configuration.id, 'configuration_revision' => 2)
    receipt = JrcServiceDesk::Intake::Submission.new.call(authority: @authority, conversation: @conversation, arguments: args)
    @demand = JrcServiceDesk::IntakeDemand.find(receipt.fetch(:id))
    @captured_context = @demand.source_context.deep_dup
  end

  def intake_responses = []
  def intake_notifications = {}
end
# rubocop:enable Metrics/MethodLength
