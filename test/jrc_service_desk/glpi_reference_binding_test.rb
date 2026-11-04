# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
module JrcServiceDesk
  module Glpi; end
end
require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/glpi/reference_binding'

class GlpiReferenceBindingTest < Minitest::Test
  def setup
    @access = Struct.new(:connection).new(Struct.new(:id, :lock_version).new(7, 0))
  end

  def test_zero_version_is_valid_and_connection_is_not_browser_selected
    assert JrcServiceDesk::Glpi::ReferenceBinding.verify!(access: @access, connection_id: '7', connection_version: '0', required: true)
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::ReferenceBinding.verify!(access: @access, connection_id: '8', connection_version: '0', required: true)
    end
    assert_equal 'configuration_changed', error.code
  end

  def test_changed_version_blocks_a_colliding_remote_identifier
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::ReferenceBinding.verify!(access: @access, connection_id: '7', connection_version: '1', required: true)
    end
    assert_equal 409, error.http_status
  end

  def test_modern_operations_require_a_complete_binding
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::ReferenceBinding.verify!(access: @access, connection_id: nil, connection_version: nil, required: true)
    end
    assert_equal 'configuration_precondition_required', error.code
    assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::ReferenceBinding.verify!(access: @access, connection_id: '7', connection_version: nil, required: true)
    end
  end

  def test_legacy_optional_empty_binding_remains_compatible
    assert JrcServiceDesk::Glpi::ReferenceBinding.verify!(access: @access, connection_id: nil, connection_version: nil, required: false)
  end
end
