require 'bundler/setup'
require 'redis'
raise 'Wrong validation target' unless ENV['RAILS_ENV'] == 'test' && ENV['POSTGRES_DATABASE'] == 'branef_glpi_test'
begin
  require 'mock_redis'
rescue LoadError
end
# The production image intentionally excludes test gems. Use only the disposable Redis.
unless defined?(MockRedis)
class MockRedis < Redis
  def initialize(*)
    super(url: ENV.fetch('REDIS_URL'))
  end
end
end
require_relative '../../config/application'
Rails.application.initialize!
# Match production class retention while exercising real native authorization per request.
Rails.application.config.cache_classes = true
Rails.application.reloader.check = -> { false }
raise 'Wrong database' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'branef_glpi_test'
ActiveJob::Base.queue_adapter = :test
ConfigLoader.new.process

$stdout.sync = true
checks = []
check = ->(name, condition) { raise "FAILED: #{name}" unless condition; checks << name; puts "PASS: #{name}" }
suffix = SecureRandom.hex(5)
account = Account.create!(name: "Branef #{suffix}", status: 'active')
account.enable_features!('jrc_service_desk')
other = Account.create!(name: "Other #{suffix}", status: 'active')
other.enable_features!('jrc_service_desk')
make_user = lambda do |label, role|
  user = User.new(name: label, email: "#{label}-#{suffix}@example.invalid", password: 'Local-Only-Validation123!', provider: 'email')
  user.skip_confirmation!
  user.save!
  membership = AccountUser.create!(account: account, user: user, role: role)
  [user, membership]
end
admin, admin_member = make_user.call('admin', 'administrator')
agent, agent_member = make_user.call('agent', 'agent')
operator = JrcServiceDesk::OperatorCompany.create!(account: account, name: 'Branef', code: suffix, active: true)
unit = JrcServiceDesk::Unit.create!(account: account, operator_company: operator, name: 'Suporte', code: 'support', active: true)
membership = JrcServiceDesk::UnitMembership.create!(account: account, unit: unit, account_user: agent_member, active: true)
admin_context = { account: account, user: admin, account_user: admin_member }
connection = JrcServiceDesk::GlpiConnection.create!(account: account, base_url: 'https://glpi.example.invalid/apirest.php',
  user_token: 'synthetic-user-token', app_token: 'synthetic-app-token', enabled: true, timezone: 'America/Sao_Paulo',
  entity_mappings: [{ entity_id: 0, unit_id: unit.id }], user_mappings: [])
ciphertext = ActiveRecord::Base.connection.select_value("SELECT user_token FROM jrc_service_desk_glpi_connections WHERE id=#{connection.id}")
check.call('credentials encrypted at rest', !ciphertext.include?('synthetic-user-token') && connection.reload.user_token == 'synthetic-user-token')

class JrcServiceDesk::Glpi::Client
  class << self
    attr_accessor :post_count, :ambiguous, :inputs, :search_response
  end
  self.post_count = 0
  self.ambiguous = false
  self.inputs = {}
  private
  def request(method, path, parameters: {}, body: nil, auth: false)
    case path
    when 'initSession/' then { 'session_token' => 'synthetic-session' }
    when 'killSession/' then true
    when 'getActiveProfile/' then { 'active_profile' => { 'id' => 6, 'name' => 'Suporte', 'ticket' => 5 } }
    when 'getMyEntities/' then { 'myentities' => [{ 'id' => 0, 'name' => 'BRANEF' }] }
    when 'listSearchOptions/Ticket/' then (JrcServiceDesk::Glpi::Normalize::FIELDS.keys + ['4']).to_h { |key| [key, { 'field' => key }] }
    when 'search/Ticket/'
      expected_scope = [{ 'field' => 80, 'searchtype' => 'equals', 'value' => 0, 'link' => 'OR' }]
      raise 'Missing authorized entity scope' unless parameters['criteria'].first['criteria'] == expected_scope
      return self.class.search_response if self.class.search_response
      { 'totalcount' => 1, 'data' => [{ '2' => 101, '1' => '<b>Consulta</b>', '80' => 'BRANEF', '12' => 1, '3' => 3,
                                     '15' => '2026-10-27 10:00:00', '82' => 0 }] }
    when 'Ticket/'
      raise 'Unexpected method' unless method == :post
      self.class.post_count += 1
      id = 1000 + self.class.post_count
      self.class.inputs[id] = body.fetch(:input)
      raise JrcServiceDesk::Glpi::Error.new('source_unavailable') if self.class.ambiguous
      { 'id' => id }
    when /\ATicket\/(\d+)\z/
      id = Regexp.last_match(1).to_i
      input = self.class.inputs[id] || {}
      { 'id' => id, 'entities_id' => id == 999 ? 999 : 0, 'status' => 1, 'priority' => 3,
        'name' => input['name'] || 'Detail', 'content' => input['content'] || 'Description' }
    when /Ticket_User/ then [{ 'id' => 1, 'tickets_id' => 101, 'users_id' => 77, 'type' => 1 }]
    when /ITILFollowup/ then [{ 'id' => 1, 'items_id' => 101, 'itemtype' => 'Ticket', 'content' => 'Public', 'is_private' => 0 },
                            { 'id' => 2, 'items_id' => 101, 'itemtype' => 'Ticket', 'content' => 'PRIVATE', 'is_private' => 1 }]
    when /TicketTask/ then []
    when %r{\ATicket/\d+/(?:ITILSolution|TicketValidation|Group_Ticket|Supplier_Ticket|Document_Item|Item_Ticket|Problem_Ticket|Change_Ticket|KnowbaseItem_Item|Log|TicketSatisfaction)/\z}
      []
    else raise "Unexpected path #{path}"
    end
  end
end

http = ActionDispatch::Integration::Session.new(Rails.application)
base = "/api/v1/accounts/#{account.id}/jrc_service_desk/glpi"
headers = admin.create_new_auth_token
http.get("#{base}/connection", headers: headers)
check.call('configuration endpoint authorized', http.response.status == 200)
check.call('configuration never returns credential values',
           !http.response.body.include?('synthetic-user-token') && !http.response.body.include?('synthetic-app-token'))
http.get("#{base}/context", headers: headers)
check.call('root entity zero is selectable', http.response.status == 200 && JSON.parse(http.response.body)['entities'].first['id'] == 0)
http.get("#{base}/tickets", headers: headers)
check.call('authorized list is normalized', http.response.status == 200 && JSON.parse(http.response.body)['items'].first['title'] == 'Consulta')
http.get("#{base}/tickets/999", headers: headers)
check.call('unmapped entity detail denied', http.response.status == 403)
http.get("/api/v1/accounts/#{other.id}/jrc_service_desk/glpi/tickets", headers: headers)
check.call('cross-account request denied', [401, 403, 404].include?(http.response.status))
agent_headers = agent.create_new_auth_token
http.get("#{base}/tickets", headers: agent_headers)
check.call('unmapped agent denied', http.response.status == 403)
connection.update!(user_mappings: [{ account_user_id: agent_member.id, glpi_user_id: 77 }])
http.get("#{base}/tickets/101", headers: agent_headers)
check.call('mapped agent can open own ticket', http.response.status == 200)
check.call('private remote followups hidden from agent', !http.response.body.include?('PRIVATE'))
http.get("#{base}/connection", headers: agent_headers)
check.call('agent cannot read integration administration', http.response.status == 403)
membership.update!(active: false)
http.get("#{base}/tickets", headers: agent_headers)
check.call('unit revocation is rechecked', http.response.status == 403)
membership.update!(active: true)

input = { 'entity_id' => 0, 'title' => 'Novo chamado', 'description' => '<script>alert(1)</script>', 'type' => 1,
          'urgency' => 3, 'impact' => 3, 'idempotency_key' => SecureRandom.uuid }
native_before = JrcServiceDesk::Ticket.count
http.post("#{base}/tickets", headers: headers, params: input, as: :json)
check.call('creation returns remote receipt', http.response.status == 201 && JSON.parse(http.response.body).dig('command', 'remote_id') == '1001')
http.post("#{base}/tickets", headers: headers, params: input, as: :json)
check.call('same key never sends second POST', http.response.status == 201 && JrcServiceDesk::Glpi::Client.post_count == 1)
check.call('remote creation does not create native ticket', JrcServiceDesk::Ticket.count == native_before)
check.call('remote description escaped', JrcServiceDesk::Glpi::Client.inputs[1001]['content'].include?('&lt;script&gt;'))
http.post("#{base}/tickets", headers: headers, params: input.merge('title' => 'Changed'), as: :json)
check.call('same key different payload conflicts', http.response.status == 409)

JrcServiceDesk::Glpi::Client.ambiguous = true
input['idempotency_key'] = SecureRandom.uuid
http.post("#{base}/tickets", headers: headers, params: input, as: :json)
receipt = JSON.parse(http.response.body).fetch('command')
check.call('timeout after POST is indeterminate', http.response.status == 202 && receipt['state'] == 'indeterminate')
http.post("#{base}/tickets", headers: headers, params: input, as: :json)
check.call('ambiguous POST is not repeated', JrcServiceDesk::Glpi::Client.post_count == 2)
http.get("#{base}/commands/lookup", headers: headers, params: { idempotency_key: input['idempotency_key'] })
check.call('receipt can be recovered without POST',
           http.response.status == 200 && JSON.parse(http.response.body).dig('command', 'id') == receipt['id'])
http.post("#{base}/commands/#{receipt['id']}/reconcile", headers: headers, params: { remote_id: 101 }, as: :json)
check.call('wrong remote ticket cannot be reconciled', http.response.status == 422)
http.post("#{base}/commands/#{receipt['id']}/reconcile", headers: headers, params: { remote_id: 1002 }, as: :json)
check.call('correlation and entity confirm ambiguous receipt',
           http.response.status == 200 && JSON.parse(http.response.body).dig('command', 'state') == 'succeeded')
http.get("#{base}/reports", headers: headers)
report = JSON.parse(http.response.body).fetch('report')
check.call('report uses authorized complete collection', http.response.status == 200 && report['total'] == 1)
check.call('missing deadline is not counted as SLA met',
           report.dig('solution_sla', 'without_deadline') == 1 && report.dig('solution_sla', 'with_deadline') == 0)
check.call('CSV cells neutralize formula injection', JrcServiceDesk::OperationalCsv.cell('=1+1') == "'=1+1")
JrcServiceDesk::Glpi::Client.search_response = { 'totalcount' => 0, 'count' => 0, 'sort' => 2, 'order' => 'ASC', 'content-range' => '0-0/0' }
http.get("#{base}/tickets", headers: headers)
check.call('empty source without data returns an empty page',
           http.response.status == 200 && JSON.parse(http.response.body)['items'] == [] && JSON.parse(http.response.body).dig('meta', 'total') == 0)
http.get("#{base}/reports", headers: headers)
check.call('empty source without data returns an empty report',
           http.response.status == 200 && JSON.parse(http.response.body).dig('report', 'total') == 0)
http.get("#{base}/reports/export", headers: headers)
check.call('empty source without data exports headers only', http.response.status == 200 && http.response.body.lines.size == 1)
JrcServiceDesk::Glpi::Client.search_response = { 'totalcount' => 0, 'data' => [] }
http.get("#{base}/tickets", headers: headers)
check.call('explicit empty source remains valid',
           http.response.status == 200 && JSON.parse(http.response.body)['items'] == [])
JrcServiceDesk::Glpi::Client.search_response = { 'totalcount' => 1 }
http.get("#{base}/tickets", headers: headers)
check.call('positive source missing data is not masked as empty',
           http.response.status == 422 && JSON.parse(http.response.body)['code'] == 'invalid_input')
http.get("#{base}/reports", headers: headers)
check.call('positive report missing data is not masked as empty',
           http.response.status == 422 && JSON.parse(http.response.body)['code'] == 'invalid_input')
JrcServiceDesk::Glpi::Client.search_response = nil
account.disable_features!('jrc_service_desk')
http.get("#{base}/tickets", headers: headers)
check.call('feature revocation is rechecked', http.response.status == 403)
puts JSON.pretty_generate(checks: checks.size, passed: checks, remote_posts: JrcServiceDesk::Glpi::Client.post_count,
                          real_glpi_requests: 0, database: ActiveRecord::Base.connection_db_config.database)
