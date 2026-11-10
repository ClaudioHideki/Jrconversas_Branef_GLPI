# frozen_string_literal: true

module BranefCoreUpgradeGuard
  def self.verify!(environment:, database:)
    return true if environment == 'test' && database == 'jrc_branef_core_upgrade_20261110_test'

    raise 'Branef upgrade fixture requires its exact disposable test database'
  end
end
