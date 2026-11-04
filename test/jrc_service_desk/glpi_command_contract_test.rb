# frozen_string_literal: true

require 'minitest/autorun'
require 'date'
require 'active_support/core_ext/object/blank'

module JrcServiceDesk
  module Glpi; end
end
require_relative '../../app/services/jrc_service_desk/glpi/operation_catalogue'
require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/glpi/identifiers'
require_relative '../../app/services/jrc_service_desk/glpi/content'
require_relative '../../app/services/jrc_service_desk/glpi/command_input'

class GlpiCommandContractTest < Minitest::Test
  def test_ticket_assignment_and_priority_use_glpi_ten_rights
    assert_equal ['ticket', 8192], JrcServiceDesk::Glpi::OperationCatalogue.fetch('ticket.assign').fetch(:source_right)
    assert_equal ['ticket', 65536], JrcServiceDesk::Glpi::OperationCatalogue.fetch('ticket.priority').fetch(:source_right)
  end

  def test_problem_and_change_have_all_mandatory_operational_transitions
    %w[problem change].each do |family|
      %w[create update delete assign priority pause resume solve close reopen].each do |verb|
        assert JrcServiceDesk::Glpi::OperationCatalogue::OPERATIONS.key?("#{family}.#{verb}"), "Missing #{family}.#{verb}"
      end
    end
  end

  def test_change_resume_uses_evaluation_and_not_nonexistent_assigned_status
    assert_equal({ 'status' => 9 }, JrcServiceDesk::Glpi::OperationCatalogue.fetch('change.resume').fetch(:defaults))
  end

  def test_children_declare_parent_key_and_cannot_accept_forged_authorship
    catalogue = JrcServiceDesk::Glpi::OperationCatalogue
    assert_equal 'items_id', catalogue.fetch('followup.create').fetch(:parent_field)
    assert_equal 'tickets_id', catalogue.fetch('task.create').fetch(:parent_field)
    catalogue::OPERATIONS.each_value do |descriptor|
      refute_includes descriptor[:fields], 'users_id_editor'
      refute_includes descriptor[:fields], 'users_id_recipient'
    end
  end

  def test_problem_and_change_group_relations_use_the_installed_glpi_classes
    assert_equal 'Group_Problem', JrcServiceDesk::Glpi::OperationCatalogue.fetch('problem_group.create').fetch(:type)
    assert_equal 'Change_Group', JrcServiceDesk::Glpi::OperationCatalogue.fetch('change_group.create').fetch(:type)
  end

  def test_planning_patch_accepts_only_the_dirty_endpoint_but_creation_requires_both
    input = JrcServiceDesk::Glpi::CommandInput.new(operation: 'task.update', target_id: 501, entity_id: 0,
      attributes: { 'parent_id' => 101, 'begin' => '2026-11-04 10:15:00' })
    assert_equal '2026-11-04 10:15:00', input.input['begin']
    refute input.input.key?('end')
    assert_raises(ArgumentError) do
      JrcServiceDesk::Glpi::CommandInput.new(operation: 'task.create', target_id: nil, entity_id: 0,
        attributes: { 'parent_id' => 101, 'content' => 'Task', 'begin' => '2026-11-04 10:15:00' })
    end
  end
end
