# frozen_string_literal: true

raise 'Laboratory confirmation required' unless ENV['GLPI_LAB_CONFIRM'] == 'isolated-synthetic'
require_relative '../jrc_service_desk/glpi_test_helper'
require_relative 'transport'
require 'json'
require 'stringio'

GlpiLabTransport.install!

module GlpiLabEvidence
  FIXTURES = JSON.parse(File.read(File.expand_path('.runtime/out/fixtures.json', __dir__)))
  raise 'Wrong GLPI laboratory version' unless FIXTURES.fetch('version') == '10.0.18'
  RESULTS = {}
  CHECKS = []
  REQUIRED = begin
    operations = %w[ticket.create ticket.update ticket.assign ticket.transfer ticket.priority ticket.pause ticket.resume
                    ticket.close ticket.reopen ticket.solve ticket.delete ticket.restore validation.request validation.decide]
    %w[followup task].each { |family| %w[create update delete].each { |verb| operations << "#{family}.#{verb}" } }
    %w[actor group supplier asset problem_link change_link knowledge_link document_link].each do |family|
      %w[create delete].each { |verb| operations << "#{family}.#{verb}" }
    end
    %w[problem change].each do |family|
      %w[create update delete assign priority pause resume close reopen solve].each { |verb| operations << "#{family}.#{verb}" }
      %w[task followup actor group].each do |child|
        (child == 'actor' || child == 'group' ? %w[create delete] : %w[create update delete]).each do |verb|
          operations << "#{family}_#{child}.#{verb}"
        end
      end
    end
    operations += %w[change_validation.request change_validation.decide]
    %w[knowledge category template].each { |family| %w[create update delete].each { |verb| operations << "#{family}.#{verb}" } }
    %w[mandatory hidden predefined].each { |family| %w[create delete].each { |verb| operations << "template_#{family}.#{verb}" } }
    (operations + ['document.upload']).freeze
  end
end

class GlpiLaboratoryTest < GlpiIntegrationTest
  FileUpload = Struct.new(:tempfile, :original_filename, :content_type)

  def setup
    super
    @fixtures = GlpiLabEvidence::FIXTURES
    mappings = [{ entity_id: 0, unit_id: @unit.id }]
    %w[support child].each do |name|
      unit = JrcServiceDesk::Unit.create!(account: @account, operator_company: @operator, name: "Synthetic #{name}", code: name, active: true)
      mappings << { entity_id: @fixtures.fetch('entities').fetch(name), unit_id: unit.id }
    end
    @connection.update!(base_url: 'https://glpi.example.invalid:14443/apirest.php',
      app_token: @fixtures.fetch('app_token'), user_token: @fixtures.fetch('user_token'),
      primary_source: true, entity_mappings: mappings,
      user_mappings: [{ account_user_id: @member.id, glpi_user_id: @fixtures.fetch('technical_user_id') }])
    @executor = JrcServiceDesk::Glpi::Execute.new
  end

  def access
    JrcServiceDesk::Glpi::Access.new(@identity)
  end

  def source(&block)
    JrcServiceDesk::Glpi::Client.new(@connection).session(&block)
  end

  def test_real_version_root_scope_complete_pagination_and_private_visibility
    source do |client|
      assert_equal '10.0.18', client.get('getGlpiConfig/').fetch('cfg_glpi').fetch('version')
      assert_equal @fixtures.fetch('technical_user_id'), client.get('getFullSession/').fetch('session').fetch('glpiID').to_i
      root = @fixtures.fetch('tickets').fetch('root')
      assert_equal 0, client.get("Ticket/#{root}").fetch('entities_id').to_i
      %w[ITILFollowup TicketTask].each do |type|
        rows = client.collection("Ticket/#{root}/#{type}/").to_a
        assert_equal 205, rows.size
        assert_equal 205, rows.map { |row| row.fetch('id') }.uniq.size
        assert_equal 1, rows.count { |row| row['is_private'].to_i == 1 }
      end
      rows = JrcServiceDesk::Glpi::TicketQuery.new(access, {}).all(client)
      refute_includes rows.map { |row| row.fetch('id').to_i }, @fixtures.fetch('tickets').fetch('foreign')
      @member.update!(role: 'agent')
      JrcServiceDesk::UnitMembership.create!(account: @account, unit: @unit, account_user: @member, active: true)
      %w[followups tasks].each do |kind|
        result = JrcServiceDesk::Glpi::ResourceQuery.new.related(access: access, client: client, kind: kind, ticket_id: root)
        assert_equal 204, result.fetch(:items).size
        refute result.fetch(:items).any? { |row| row['is_private'].to_i == 1 }
      end
    end
    GlpiLabEvidence::CHECKS << 'actual root0, 205 followups, 205 tasks, private visibility and entity scope'
  end

  def test_real_limited_profile_and_foreign_unit_denials
    @connection.update!(user_token: @fixtures.fetch('limited_token'))
    source do |client|
      own = @fixtures.fetch('tickets').fetch('limited_own')
      assert_equal own, client.get("Ticket/#{own}").fetch('id').to_i
      error = assert_raises(JrcServiceDesk::Glpi::Error) { client.get("Ticket/#{@fixtures.fetch('tickets').fetch('root')}") }
      assert_equal 403, error.http_status
    end
    before = GlpiLabTransport::COUNTS[:post]
    receipt = @executor.call(access: access, operation: 'ticket.create', target_id: nil, entity_id: 0,
      attributes: { 'name' => 'Synthetic forbidden write', 'content' => 'Synthetic', 'type' => 1, 'urgency' => 3, 'impact' => 3 },
      idempotency_key: SecureRandom.uuid)
    assert_equal 'rejected', receipt.fetch(:state)
    assert_equal 'operation_not_permitted', receipt.fetch(:error_code)
    assert_equal before, GlpiLabTransport::COUNTS[:post]
    @connection.update!(user_token: @fixtures.fetch('user_token'))
    source do |client|
      foreign = @fixtures.fetch('tickets').fetch('foreign')
      assert_equal foreign, client.get("Ticket/#{foreign}").fetch('id').to_i
      assert_raises(Pundit::NotAuthorizedError) do
        JrcServiceDesk::Glpi::ResourceQuery.new.raw(access: access, client: client, kind: 'tickets', id: foreign)
      end
    end
    GlpiLabEvidence::CHECKS << 'actual limited source profile and JRC foreign-unit refusals'
  end

  def test_actual_projection_and_overview_remain_derived_and_dated
    run = JrcServiceDesk::Glpi::SyncTickets.new.call(connection: @connection, actor: @member)
    assert_equal 'complete', run.state, "Synthetic synchronization: #{run.coverage.values.filter_map { |entry| entry['error'] if entry.is_a?(Hash) }.uniq}"
    snapshots = JrcServiceDesk::GlpiTicketSnapshot.current_for(@connection)
    assert snapshots.exists?(remote_id: @fixtures.fetch('tickets').fetch('root'), entity_id: 0)
    refute snapshots.exists?(remote_id: @fixtures.fetch('tickets').fetch('foreign'))
    assert_equal 0, JrcServiceDesk::Ticket.where(account: @account).count
    overview = JrcServiceDesk::Glpi::Overview.new
    assert_equal overview.list(access: access, filters: {}).fetch(:meta).fetch(:total), overview.call(access: access, filters: {}).fetch(:total)
    assert overview.call(access: access, filters: {}).fetch(:observed_at)
    GlpiLabEvidence::CHECKS << 'actual derived projection, root mapping, dated consistent overview, no native copies'
  end

  def test_all_required_named_commands_against_real_glpi
    assert_equal GlpiLabEvidence::REQUIRED.sort, JrcServiceDesk::Glpi::OperationCatalogue::OPERATIONS.keys.sort
    failures = []
    source do |client|
      @fixture_client = client
      (GlpiLabEvidence::REQUIRED - ['document.upload']).each do |operation|
        begin
          descriptor = JrcServiceDesk::Glpi::OperationCatalogue.fetch(operation)
          attributes = operation_attributes(operation)
          parent = descriptor[:parent] && fixture_object(descriptor[:parent])
          attributes['parent_id'] = parent if parent
          target = descriptor[:verb] == 'post' ? nil : fixture_target(operation, descriptor, parent)
          version_row = target ? client.get("#{descriptor[:type]}/#{target}") : parent && client.get("#{descriptor[:parent]}/#{parent}")
          receipt = @executor.call(access: access, operation: operation, target_id: target, entity_id: 0,
            attributes: attributes, expected_version: version_row && version_row['date_mod'],
            idempotency_key: SecureRandom.uuid, reason: descriptor[:verb] == 'delete' ? 'Synthetic laboratory cleanup' : nil)
          GlpiLabEvidence::RESULTS[operation] = receipt.slice(:state, :error_code, :technical_user_id, :itemtype)
          assert_equal 'succeeded', receipt.fetch(:state), "#{operation}: #{receipt.slice(:state, :error_code).to_json}"
          assert_equal @fixtures.fetch('technical_user_id'), receipt.fetch(:technical_user_id)
          assert_equal @member.id.to_s, receipt.fetch(:initiator_account_user_id)
          assert receipt.fetch(:result).fetch('verified')
          verify_semantics(client, operation, receipt)
        rescue StandardError, Minitest::Assertion => error
          GlpiLabEvidence::RESULTS[operation] ||= { state: 'fixture_or_contract_error', error_code: error.respond_to?(:code) ? error.code : error.class.name }
          failures << "#{operation}: #{error.respond_to?(:code) ? error.code : error.message.to_s.first(180)}"
        end
      end
    end
    assert_empty failures, failures.join("\n")
    GlpiLabEvidence::CHECKS << 'all required named command verbs, source readbacks and technical/JRC authorship'
  end

  def test_actual_multipart_document_bytes_links_idempotency_and_unlink
    source do |client|
      @fixture_client = client
      first = fixture_object('Ticket')
      second = fixture_object('Ticket')
      bytes = "SYNTHETIC JRC GLPI DOCUMENT\n"
      file = FileUpload.new(StringIO.new(bytes), 'synthetic-lab.txt', 'text/plain')
      documents = JrcServiceDesk::Glpi::Documents.new
      key = SecureRandom.uuid
      receipt = documents.upload(access: access, ticket_id: first, file: file, idempotency_key: key)
      GlpiLabEvidence::RESULTS['document.upload'] = receipt.slice(:state, :error_code, :technical_user_id)
      assert_equal 'succeeded', receipt.fetch(:state), receipt.slice(:state, :error_code).to_json
      assert_equal @fixtures.fetch('technical_user_id'), receipt.fetch(:technical_user_id)
      assert_equal receipt.fetch(:id), documents.upload(access: access, ticket_id: first, file: file, idempotency_key: key).fetch(:id)
      id = receipt.fetch(:remote_id).to_i
      assert_equal bytes, documents.download(access: access, client: client, ticket_id: first, document_id: id).fetch(:bytes)
      link = @executor.call(access: access, operation: 'document_link.create', target_id: nil, entity_id: 0,
        attributes: { 'parent_id' => second, 'documents_id' => id }, idempotency_key: SecureRandom.uuid)
      assert_equal 'succeeded', link.fetch(:state)
      unlink = @executor.call(access: access, operation: 'document_link.delete', target_id: receipt.fetch(:result).fetch('link_id'), entity_id: 0,
        attributes: { 'parent_id' => first }, idempotency_key: SecureRandom.uuid)
      assert_equal 'succeeded', unlink.fetch(:state)
      assert_equal id, client.get("Document/#{id}").fetch('id').to_i
      assert_equal bytes, documents.download(access: access, client: client, ticket_id: second, document_id: id).fetch(:bytes)
      assert_raises(Pundit::NotAuthorizedError) { documents.download(access: access, client: client, ticket_id: first, document_id: id) }
    end
    GlpiLabEvidence::CHECKS << 'actual multipart file bytes, durable idempotency, shared link removal without file deletion'
  end

  def test_transport_refuses_every_non_laboratory_target
    %w[http://glpi.example.invalid:14443/apirest.php/Ticket https://localhost:14443/apirest.php/Ticket
       https://glpi.example.invalid:443/apirest.php/Ticket https://glpi.example.invalid:14443/other
       https://user:secret@glpi.example.invalid:14443/apirest.php/Ticket https://customer.example.com/apirest.php/Ticket].each do |url|
      assert_raises(SecurityError) { GlpiLabTransport.target!(url) }
    end
    GlpiLabEvidence::CHECKS << 'test transport exact host, port, scheme, path, no userinfo, no proxy, trusted CA'
  end

  private

  def raw_create(type, attributes)
    response = @fixture_client.create_item(type, attributes)
    JrcServiceDesk::Input.id(response.fetch('id'))
  end

  def fixture_object(type)
    common = { 'name' => "SYNTHETIC #{type} #{SecureRandom.hex(5)}", 'entities_id' => 0 }
    case type
    when 'Ticket'
      raw_create(type, common.merge('content' => 'Synthetic disposable ticket', 'type' => 1, 'urgency' => 3, 'impact' => 3,
        '_users_id_requester' => @fixtures.fetch('technical_user_id')))
    when 'Problem', 'Change'
      raw_create(type, common.merge('content' => 'Synthetic disposable ITIL object', 'urgency' => 3, 'impact' => 3))
    when 'KnowbaseItem'
      raw_create(type, common.except('entities_id').merge('answer' => 'Synthetic knowledge',
        '_visibility' => { '_type' => 'Entity', 'entities_id' => 0, 'is_recursive' => 0 }))
    when 'Document'
      response = @fixture_client.upload_document(common, bytes: "SYNTHETIC LINK FIXTURE\n", filename: "fixture_#{SecureRandom.hex(8)}.txt", content_type: 'text/plain')
      JrcServiceDesk::Input.id(response.fetch('id'))
    when 'ITILCategory', 'TicketTemplate'
      raw_create(type, common.merge('is_recursive' => 1))
    else
      raise "Unsupported synthetic fixture type #{type}"
    end
  end

  def operation_attributes(operation)
    family, verb = operation.split('.')
    return {} if verb == 'delete' || %w[pause resume close reopen restore].include?(verb)
    return { 'priority' => 5 } if verb == 'priority'
    return { '_users_id_assign' => @fixtures.fetch('technical_user_id'), '_groups_id_assign' => @fixtures.fetch('catalogues').fetch('group') } if verb == 'assign'
    return { 'entities_id' => @fixtures.fetch('entities').fetch('support') } if verb == 'transfer'
    return { 'content' => 'Synthetic confirmed solution', 'solutiontypes_id' => @fixtures.fetch('catalogues').fetch('solution_type') } if verb == 'solve'
    if family.end_with?('validation')
      return verb == 'request' ? { 'users_id_validate' => @fixtures.fetch('technical_user_id'), 'comment_submission' => 'Synthetic validation request' } :
        { 'status' => 3, 'comment_validation' => 'Synthetic approved validation' }
    end
    if family.start_with?('template_')
      return { 'num' => { 'template_mandatory' => 1, 'template_hidden' => 21, 'template_predefined' => 14 }.fetch(family) }
        .tap { |values| values['value'] = '1' if family == 'template_predefined' }
    end
    case family
    when 'ticket'
      { 'name' => "Synthetic #{operation}", 'content' => 'Synthetic ticket content', 'type' => 1, 'urgency' => 3, 'impact' => 3 }
    when 'problem', 'change'
      { 'name' => "Synthetic #{operation}", 'content' => 'Synthetic related content', 'urgency' => 3, 'impact' => 3 }
    when 'knowledge'
      { 'name' => "Synthetic #{operation}", 'answer' => 'Synthetic knowledge answer', 'is_faq' => 0 }
    when 'category', 'template'
      { 'name' => "Synthetic #{operation}", 'comment' => 'Synthetic catalogue' }
    when /followup\z/
      { 'content' => 'Synthetic private followup', 'is_private' => 1 }
    when /task\z/
      { 'content' => 'Synthetic planned task', 'is_private' => 1, 'actiontime' => 600, 'state' => 1,
        'users_id_tech' => @fixtures.fetch('technical_user_id'), 'groups_id_tech' => @fixtures.fetch('catalogues').fetch('group'),
        'taskcategories_id' => @fixtures.fetch('catalogues').fetch('task_category'),
        'begin' => 1.hour.from_now.strftime('%Y-%m-%d %H:%M:%S'), 'end' => 2.hours.from_now.strftime('%Y-%m-%d %H:%M:%S') }
    when /actor\z/
      { 'users_id' => @fixtures.fetch('technical_user_id'), 'type' => 2 }
    when /group\z/
      { 'groups_id' => @fixtures.fetch('catalogues').fetch('group'), 'type' => 2 }
    when 'supplier'
      { 'suppliers_id' => @fixtures.fetch('catalogues').fetch('supplier'), 'type' => 2 }
    when 'asset'
      { 'itemtype' => 'Computer', 'items_id' => @fixtures.fetch('catalogues').fetch('computer') }
    when 'problem_link'
      { 'problems_id' => fixture_object('Problem') }
    when 'change_link'
      { 'changes_id' => fixture_object('Change') }
    when 'knowledge_link'
      { 'knowbaseitems_id' => fixture_object('KnowbaseItem') }
    when 'document_link'
      { 'documents_id' => fixture_object('Document') }
    else
      raise "Missing laboratory input for #{operation}"
    end
  end

  def fixture_target(operation, descriptor, parent)
    if parent
      family = operation.split('.').first
      input = operation_attributes("#{family}.#{family.end_with?('validation') ? 'request' : 'create'}")
      input[descriptor.fetch(:parent_field)] = parent
      input.merge!(descriptor[:defaults])
      return raw_create(descriptor[:type], input)
    end
    id = fixture_object(descriptor[:type])
    verb = operation.split('.').last
    if %w[close reopen].include?(verb)
      raw_create('ITILSolution', 'itemtype' => descriptor[:type], 'items_id' => id, 'content' => 'Synthetic fixture solution')
      @fixture_client.update_item(descriptor[:type], id, 'status' => 6) if verb == 'reopen'
    elsif verb == 'resume'
      @fixture_client.update_item(descriptor[:type], id, 'status' => 4)
    elsif verb == 'restore'
      @fixture_client.delete_item(descriptor[:type], id)
    end
    id
  end

  def verify_semantics(client, operation, receipt)
    expected_status = { 'ticket.pause' => 4, 'ticket.resume' => 2, 'ticket.close' => 6, 'ticket.reopen' => 2,
      'problem.pause' => 4, 'problem.resume' => 2, 'problem.close' => 6, 'problem.reopen' => 2,
      'change.pause' => 4, 'change.resume' => 9, 'change.close' => 6, 'change.reopen' => 9 }
    return unless expected_status.key?(operation) || operation.end_with?('.priority', '.restore', '.transfer')

    row = client.get("#{receipt.fetch(:itemtype)}/#{receipt.fetch(:remote_id)}")
    assert_equal expected_status.fetch(operation), row.fetch('status').to_i if expected_status.key?(operation)
    assert_equal 5, row.fetch('priority').to_i if operation.end_with?('.priority')
    assert_equal 0, row.fetch('is_deleted').to_i if operation.end_with?('.restore')
    assert_equal @fixtures.fetch('entities').fetch('support'), row.fetch('entities_id').to_i if operation.end_with?('.transfer')
  end
end

Minitest.after_run do
  missing = GlpiLabEvidence::REQUIRED - GlpiLabEvidence::RESULTS.keys
  evidence = { version: GlpiLabEvidence::FIXTURES.fetch('version'), customer_requests: 0, synthetic_only: true,
    required_operations: GlpiLabEvidence::REQUIRED.size, operations: GlpiLabEvidence::RESULTS,
    untested_operations: missing, checks: GlpiLabEvidence::CHECKS, transport_requests: GlpiLabTransport::COUNTS,
    actual_jrc_components: %w[Client TicketQuery ResourceQuery SyncTickets Overview Execute Documents] }
  File.write(File.expand_path('.runtime/laboratory-results.json', __dir__), JSON.pretty_generate(evidence))
  puts JSON.generate(version: evidence[:version], required_operations: evidence[:required_operations],
    recorded_operations: evidence[:operations].size, untested: missing.size, customer_requests: 0)
  exit 1 unless missing.empty?
end
