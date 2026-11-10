# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../script/branef_core_upgrade_guard'

class BranefCoreUpgradeGuardTest < Minitest::Test
  def test_accepts_only_the_named_test_target
    assert BranefCoreUpgradeGuard.verify!(environment: 'test', database: 'jrc_branef_core_upgrade_20261110_test')
  end

  def test_refuses_production_and_other_test_databases
    %w[production development].each do |environment|
      assert_raises(RuntimeError) { BranefCoreUpgradeGuard.verify!(environment: environment, database: 'jrc_branef_core_upgrade_20261110_test') }
    end
    %w[branef_glpi_test jrc_broker production_test].each do |database|
      assert_raises(RuntimeError) { BranefCoreUpgradeGuard.verify!(environment: 'test', database: database) }
    end
  end
end
