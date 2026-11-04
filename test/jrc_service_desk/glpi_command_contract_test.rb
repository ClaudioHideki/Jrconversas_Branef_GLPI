# frozen_string_literal: true

require 'minitest/autorun'

module JrcServiceDesk
  module Glpi; end
end
require_relative '../../app/services/jrc_service_desk/glpi/operation_catalogue'

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

  def test_all_nine_template_verbs_use_the_real_inherited_itiltemplate_profile_right
    operations = JrcServiceDesk::Glpi::OperationCatalogue::OPERATIONS.select { |name, _| name.start_with?('template') }
    assert_equal 9, operations.size
    operations.each do |name, descriptor|
      assert_equal 'itiltemplate', descriptor[:source_right].first, name
    end
  end
end
