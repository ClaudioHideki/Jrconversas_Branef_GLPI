# frozen_string_literal: true

# Run through Rails runner in the Branef Rails container. Read-only diagnostics;
# never prints ENV, credentials, ticket descriptions or object download URLs.
require 'json'
require 'net/http'

expected = ENV.fetch('EXPECTED_BRANEF_REVISION')
raise 'Expected revision must be a full Git SHA' unless expected.match?(/\A[0-9a-f]{40}\z/)
raise 'Wrong database/environment' unless Rails.env.production? && ActiveRecord::Base.connection_db_config.database == 'jrc_branef'
raise 'Wrong public installation' unless ENV['FRONTEND_URL'].to_s.delete_suffix('/') == 'https://branef.jrcws.cloud'

actual = Rails.root.join('.git_sha').read.strip
raise 'Running image differs from the approved revision' unless actual == expected

versions = ActiveRecord::Base.connection.select_values('SELECT version FROM schema_migrations')
required = Dir[Rails.root.join('db/migrate/*glpi*.rb')].map { |path| File.basename(path).split('_').first }
missing = required - versions
raise "GLPI migrations pending: #{missing.join(',')}" if missing.any?

account = Account.find(3)
raise 'Unexpected target account' unless account.name.to_s.strip.casecmp('BRANEF').zero?

def diagnostic
  yield
rescue StandardError => error
  { error: error.respond_to?(:code) ? error.code : error.class.name }
end

connection = JrcServiceDesk::GlpiConnection.find_by(account_id: account.id)
report = { observed_at: Time.current.iso8601, running_revision: actual, account_id: account.id, account_name: account.name,
           missing_glpi_migrations: missing, service_desk_enabled: account.feature_enabled?('jrc_service_desk') }
report[:members] = AccountUser.where(account_id: account.id).includes(:user).order(:id).map do |member|
  { account_user_id: member.id, user_id: member.user_id, email: member.user.email, role: member.role }
end
report[:operators] = JrcServiceDesk::OperatorCompany.where(account_id: account.id).order(:id).pluck(:id, :name, :active)
report[:units] = JrcServiceDesk::Unit.where(account_id: account.id).order(:id).pluck(:id, :operator_company_id, :name, :code, :active)
report[:unit_memberships] = JrcServiceDesk::UnitMembership.where(account_id: account.id).order(:id)
  .pluck(:id, :unit_id, :account_user_id, :active, :administrative_actor)
report[:glpi] = connection && { id: connection.id, enabled: connection.enabled?, primary_source: connection.primary_source?,
                               base_url: connection.base_url, version: connection.lock_version, entity_mappings: connection.entity_mappings }
report[:redis] = diagnostic do
  redis = Redis.new(url: ENV.fetch('REDIS_URL'))
  begin
    redis.ping
  ensure
    redis.close
  end
end
report[:storage] = diagnostic do
  { service: ActiveStorage::Blob.service.class.name, bucket: ENV['STORAGE_BUCKET_NAME'],
    read_probe_exists: ActiveStorage::Blob.service.exist?('branef-deployment-read-probe') }
end
report[:nico] = diagnostic do
  http = Net::HTTP.new('nico-runtime', 3108, nil)
  http.open_timeout = 5
  http.read_timeout = 5
  response = http.get('/health')
  body = JSON.parse(response.body)
  { http_status: response.code.to_i, ready: body['ready'], configured_mode: ENV['NICO_MODE'] }
end
report[:source_read] = diagnostic do
  raise 'GLPI connection is disabled or absent' unless connection&.enabled?

  JrcServiceDesk::Glpi::Client.new(connection).session do |client|
    profile = client.get('getActiveProfile/').fetch('active_profile')
    available = client.get('getMyEntities/', 'is_recursive' => 'true').fetch('myentities')
    active = client.get('getActiveEntities/').fetch('active_entity')
    { profile: profile.slice('id', 'name'), permitted_entity_ids: available.map { |row| row.fetch('id').to_i }.uniq.sort,
      active_entity_ids: active.fetch('active_entities').map { |row| row.fetch('id').to_i }.uniq.sort,
      ticket_read_all_announced: (profile.fetch('ticket', 0).to_i & 1024).positive?,
      document_read_announced: (profile.fetch('document', 0).to_i & 1).positive?, business_writes: 0 }
  end
end
puts JSON.pretty_generate(report)
