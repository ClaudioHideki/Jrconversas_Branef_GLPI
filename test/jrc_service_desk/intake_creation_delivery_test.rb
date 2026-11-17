# frozen_string_literal: true

require_relative 'intake_route_contract_test'
require_relative '../../app/services/jrc_service_desk/intake/delivery'
require_relative '../../app/services/jrc_service_desk/glpi/execute'

module Pundit
  class NotAuthorizedError < StandardError; end
end

class IntakeCreationDeliveryTest < Minitest::Test
  def test_creation_attributes_do_not_trigger_assignment_or_sla_patch
    delivery = JrcServiceDesk::Intake::Delivery.new
    mapping = Struct.new(:route) do
      def creation_attributes? = true
      def sla_attributes = { 'slas_id_tto' => 12, 'slas_id_ttr' => 13 }
    end.new({})
    delivery.instance_variable_set(:@mapping, mapping)
    stages = []
    delivery.define_singleton_method(:prepare!) {}
    delivery.define_singleton_method(:create_ticket!) { true }
    delivery.define_singleton_method(:record_link!) { stages << 'link' }
    delivery.define_singleton_method(:record_stage) { |name, result| stages << [name, result] }
    delivery.define_singleton_method(:assignment!) { flunk 'No separate assignment write' }
    delivery.define_singleton_method(:sla!) { flunk 'No separate SLA write' }
    delivery.define_singleton_method(:finish) { |state| state }
    assert_equal 'confirmed', delivery.send(:perform_delivery)
    assert_equal ['link', ['assignment', { state: 'succeeded' }], ['sla', { state: 'succeeded' }]], stages
  end

  def test_uncertain_creation_does_not_proceed_to_link_or_assignment
    delivery = JrcServiceDesk::Intake::Delivery.new
    delivery.instance_variable_set(:@demand, Struct.new(:receipt).new({ state: 'indeterminate' }))
    delivery.define_singleton_method(:prepare!) {}
    delivery.define_singleton_method(:create_ticket!) { false }
    delivery.define_singleton_method(:record_link!) { flunk 'Uncertain ticket must not be linked or resent' }
    assert_equal({ state: 'indeterminate' }, delivery.send(:perform_delivery))
  end

  def test_assignment_at_creation_still_requires_glpi_assignment_right
    executor = JrcServiceDesk::Glpi::Execute.new
    command = Struct.new(:operation, :request_payload, :itemtype).new('ticket.create', { '_groups_id_assign' => 1 }, 'Ticket')
    descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch('ticket.create')
    assert_raises(JrcServiceDesk::Glpi::Error) do
      executor.send(:authorize_source!, { 'ticket' => 4 }, command, descriptor, nil, nil, 100)
    end
    executor.send(:authorize_source!, { 'ticket' => 4 | 8192 }, command, descriptor, nil, nil, 100)
  end

  def test_sla_at_creation_still_requires_glpi_update_right
    executor = JrcServiceDesk::Glpi::Execute.new
    command = Struct.new(:operation, :request_payload, :itemtype).new('ticket.create', { 'slas_id_tto' => 12 }, 'Ticket')
    descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch('ticket.create')
    assert_raises(JrcServiceDesk::Glpi::Error) do
      executor.send(:authorize_source!, { 'ticket' => 4 }, command, descriptor, nil, nil, 100)
    end
    executor.send(:authorize_source!, { 'ticket' => 4 | 2 }, command, descriptor, nil, nil, 100)
  end

  def test_anonymous_readback_verifies_ticket_email_and_notification
    rows = [{ 'tickets_id' => 501, 'type' => 1, 'users_id' => 0,
              'alternative_email' => 'request@example.invalid', 'use_notification' => 1 }]
    client = Object.new
    client.define_singleton_method(:collection) { |_path| rows }
    notification = { 'use_notification' => [1], 'alternative_email' => ['request@example.invalid'] }
    executor = JrcServiceDesk::Glpi::Execute.new
    assert executor.send(:anonymous_requester_matches?, client, 501, notification)
    rows[0]['tickets_id'] = 502
    refute executor.send(:anonymous_requester_matches?, client, 501, notification)
    rows[0]['tickets_id'] = 501
    rows[0]['alternative_email'] = 'other@example.invalid'
    refute executor.send(:anonymous_requester_matches?, client, 501, notification)
  end
end
