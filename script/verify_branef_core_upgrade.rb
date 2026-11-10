# frozen_string_literal: true

require 'json'
require_relative 'branef_core_upgrade_guard'

connection = ActiveRecord::Base.connection
BranefCoreUpgradeGuard.verify!(environment: Rails.env.to_s, database: ActiveRecord::Base.connection_db_config.database)
reference = JSON.parse(File.read(Rails.root.join('deploy/jrc/EXTENSION-REFERENCE.json')))
baseline = JSON.parse(File.read(ARGV.fetch(0)))
raise 'Unexpected baseline fixture' unless baseline.fetch('baseline') == reference.fetch('extensionBaselineSha')
versions = baseline.fetch('versions')
raise 'Invalid synthetic migration inventory' unless versions.all? { |version| version.match?(/\A\d{14}\z/) } && versions.uniq == versions

# schema:load normally marks every checked-out migration up to its version.
# Reproduce only the versions actually present in the historical source tree.
# This metadata rewrite is guarded above and is exclusive to a disposable CI DB.
connection.execute('DELETE FROM schema_migrations')
versions.each { |version| connection.execute("INSERT INTO schema_migrations (version) VALUES (#{connection.quote(version)})") }
account_id = connection.select_value("INSERT INTO accounts (name, created_at, updated_at) VALUES ('Synthetic Branef upgrade', NOW(), NOW()) RETURNING id")
contact_id = connection.select_value(<<~SQL.squish)
  INSERT INTO contacts (name, account_id, identifier, custom_attributes, created_at, updated_at)
  VALUES ('Synthetic preserved contact', #{connection.quote(account_id)}, 'upgrade-fixture', '{"source":"fixture"}'::jsonb, NOW(), NOW()) RETURNING id
SQL
glpi_id = connection.select_value(<<~SQL.squish)
  INSERT INTO jrc_service_desk_glpi_connections (account_id, base_url, user_token, app_token, created_at, updated_at)
  VALUES (#{connection.quote(account_id)}, 'https://source.example.invalid', 'synthetic-disabled-user', 'synthetic-disabled-app', NOW(), NOW()) RETURNING id
SQL
rows = { 'accounts' => account_id, 'contacts' => contact_id, 'jrc_service_desk_glpi_connections' => glpi_id }.map do |table, id|
  columns = connection.columns(table).map(&:name).map { |name| connection.quote_column_name(name) }.join(', ')
  query = "SELECT #{columns} FROM #{connection.quote_table_name(table)} WHERE id = #{connection.quote(id)}"
  [query, connection.select_one(query)]
end
glpi_indexes = connection.indexes(:jrc_service_desk_glpi_connections).map { |index| [index.name, index.columns, index.unique] }
context = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate'))
pending_before = context.migrations.reject { |migration| versions.include?(migration.version.to_s) }.map(&:version)
raise 'The historical import was not exercised' unless pending_before.include?(20261102090000)
context.migrate
raise 'Pending migrations after historical core import' if context.needs_migration?
raise 'A synthetic historical row changed during upgrade' unless rows.all? { |query, expected| connection.select_one(query) == expected }
raise 'GLPI indexes changed during generic core upgrade' unless connection.indexes(:jrc_service_desk_glpi_connections).map { |index| [index.name, index.columns, index.unique] } == glpi_indexes
%w[jrc_broker_webhook_obligations jrc_broker_connection_events jrc_migration_media_objects jrc_contact_center_call_observations].each do |table|
  raise "Missing imported core table: #{table}" unless connection.table_exists?(table)
end
raise 'Missing core Projects permissions' unless connection.column_exists?(:account_users, :jrc_projects_permissions)
guards = connection.select_values("SELECT tgname FROM pg_trigger WHERE tgrelid = 'jrc_migration_media_objects'::regclass AND NOT tgisinternal")
raise 'Imported custody guards missing' unless (%w[jrc_migration_media_owner_rows jrc_migration_media_owner_truncate] - guards).empty?
puts JSON.generate(result: 'PASS', baseline: baseline.fetch('baseline'), applied_migrations: pending_before, preserved_rows: rows.length,
                   glpi_indexes_preserved: true, custody_guards: true, physical_channel: false)
