# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'redis'
raise 'Wrong validation target' unless ENV['RAILS_ENV'] == 'test' && ENV['POSTGRES_DATABASE'] == 'branef_glpi_test'

begin
  require 'mock_redis'
rescue LoadError
  class MockRedis < Redis
    def initialize(*)
      super(url: ENV.fetch('REDIS_URL'))
    end
  end
end
require_relative '../../config/application'
Rails.application.initialize!
Rails.application.config.cache_classes = true
Rails.application.reloader.check = -> { false }
raise 'Wrong database' unless ActiveRecord::Base.connection_db_config.database == 'branef_glpi_test'

ActiveJob::Base.queue_adapter = :test
ConfigLoader.new.process

class GlpiIntegrationTest < Minitest::Test
  def setup
    @account = Account.create!(name: "GLPI #{SecureRandom.hex(6)}", status: 'active')
    @account.enable_features!('jrc_service_desk')
    @user = User.new(name: 'Lab administrator', email: "#{SecureRandom.hex(8)}@example.invalid",
                     password: 'Synthetic-Lab-Only123!', provider: 'email')
    @user.skip_confirmation!
    @user.save!
    @member = AccountUser.create!(account: @account, user: @user, role: 'administrator')
    @operator = JrcServiceDesk::OperatorCompany.create!(account: @account, name: 'Lab', code: SecureRandom.hex(6), active: true)
    @unit = JrcServiceDesk::Unit.create!(account: @account, operator_company: @operator, name: 'Root', code: 'root', active: true)
    @connection = JrcServiceDesk::GlpiConnection.create!(account: @account, base_url: 'https://glpi.example.invalid/apirest.php',
      user_token: 'synthetic-user', app_token: 'synthetic-app', enabled: true, timezone: 'UTC',
      entity_mappings: [{ entity_id: 0, unit_id: @unit.id }], user_mappings: [])
    @identity = { account: @account, user: @user, account_user: @member }
  end

  def teardown
    # A disposable database is deliberately retained until the complete run finishes.
    Current.reset
  end
end
