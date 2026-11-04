# frozen_string_literal: true

# These tests use real GLPI metadata, permissions, writes and independent GETs.
# A backend that merely sends Ticket.add defaults cannot satisfy these assertions.
class GlpiTemplateLaboratoryTest < GlpiIntegrationTest
  def setup
    super
    @fixtures = GlpiLabEvidence::FIXTURES.fetch('templates')
    @entity = @fixtures.fetch('entities').fetch('child')
    mappings = [{ entity_id: 0, unit_id: @unit.id }]
    @fixtures.fetch('entities').each do |label, entity|
      unit = JrcServiceDesk::Unit.create!(account: @account, operator_company: @operator,
        name: "Synthetic template #{label}", code: label, active: true)
      mappings << { entity_id: entity, unit_id: unit.id }
    end
    @connection.update!(base_url: 'https://glpi.example.invalid:14443/apirest.php',
      app_token: GlpiLabEvidence::FIXTURES.fetch('app_token'), primary_source: true, entity_mappings: mappings,
      user_token: @fixtures.fetch('users').fetch('base').fetch('token'))
    @executor = JrcServiceDesk::Glpi::Execute.new
  end

  def test_actual_automatic_entity_profile_and_typed_category_models_apply_source_values
    category = @fixtures.fetch('category_id')
    cases = [
      ['base', {}, 'entity', 'entity', 2, 0, 4],
      ['profile', { 'type' => 1 }, 'profile', 'profile', 1, 0, 5],
      ['profile', { 'type' => 1, 'category_id' => category }, 'incident', 'category', 1, category, 2],
      ['base', { 'type' => 2, 'category_id' => category }, 'request', 'category', 2, category, 1],
      ['base', { 'category_id' => category }, 'request', 'category', 2, category, 1],
      ['redirect', { 'type' => 1 }, 'request', 'category_predefined', 1, 0, 1]
    ]
    cases.each do |user, filters, model, provenance, type, category_id, urgency|
      @connection.update!(user_token: @fixtures.fetch('users').fetch(user).fetch('token'))
      form = source { |client| ticket_form(client, filters) }
      assert_equal @fixtures.fetch('models').fetch(model), form.fetch(:template_id)
      assert_equal provenance, form.fetch(:template_source)
      assert_equal type, form.fetch(:type)
      assert_equal category_id, form.fetch(:category_id)
      assert_equal urgency, form.fetch(:predefined).fetch('urgency')
      assert form.fetch(:supported), form.fetch(:unsupported_required).inspect
      refute_includes form.fetch(:hidden), 'type' if provenance == 'category'
      attributes = { 'content' => 'Synthetic actual automatic model issue' }
      attributes['type'] = filters['type'] if filters.key?('type')
      attributes['itilcategories_id'] = filters['category_id'] if filters.key?('category_id')
      receipt = create(attributes, template_version: form.fetch(:version))
      assert_equal 'succeeded', receipt.fetch(:state), "#{user}/#{model}: #{receipt.slice(:state, :error_code)}"
      source do |client|
        persisted = client.get("Ticket/#{receipt.fetch(:remote_id)}")
        assert_equal "SYNTHETIC MODEL TITLE #{model}", persisted.fetch('name')
        assert_equal type, persisted.fetch('type').to_i
        assert_equal category_id, persisted.fetch('itilcategories_id').to_i
        assert_equal urgency, persisted.fetch('urgency').to_i
        assert_equal @entity, persisted.fetch('entities_id').to_i
      end
      stored = JrcServiceDesk::GlpiCommand.find(receipt.fetch(:id))
      assert_equal @fixtures.fetch('models').fetch(model), stored.request_payload.fetch('_tickettemplate')
      assert_equal form.fetch(:version), stored.template_version
      GlpiLabEvidence::CHECKS << "actual #{provenance} model #{model}, typed source defaults and persisted selector"
    end
  end

  def test_actual_explicit_model_preserves_operator_edits_hidden_defaults_requester_and_idempotency
    model = @fixtures.fetch('models').fetch('explicit')
    requester = @fixtures.fetch('users').fetch('base').fetch('id')
    form = source { |client| ticket_form(client, 'template_id' => model, 'type' => 1) }
    assert_equal 'explicit', form.fetch(:template_source)
    assert_equal ['urgency'], form.fetch(:hidden)
    assert_includes form.fetch(:required), '_users_id_requester'
    assert_equal 'Describe the synthetic issue', form.fetch(:predefined).fetch('content')
    assert_includes form.fetch(:predefined_html).fetch('content'), '<p>'
    key = SecureRandom.uuid
    attributes = { 'template_id' => model, 'type' => 1, 'name' => 'Synthetic operator title',
      'content' => '<p>Actual <strong>operator</strong> issue</p><table><tr><td>Evidence</td></tr></table>',
      'content_format' => 'rich', 'impact' => 3, '_users_id_requester' => requester }
    before = GlpiLabTransport::ITEM_MUTATIONS[:post]
    receipt = create(attributes, template_version: form.fetch(:version), idempotency_key: key)
    assert_equal 'succeeded', receipt.fetch(:state), receipt.slice(:state, :error_code).inspect
    assert_equal before + 1, GlpiLabTransport::ITEM_MUTATIONS[:post]
    assert_equal receipt.fetch(:id), create(attributes, template_version: form.fetch(:version), idempotency_key: key).fetch(:id)
    assert_equal before + 1, GlpiLabTransport::ITEM_MUTATIONS[:post]
    source do |client|
      persisted = client.get("Ticket/#{receipt.fetch(:remote_id)}")
      assert_equal 'Synthetic operator title', persisted.fetch('name')
      assert_equal 4, persisted.fetch('urgency').to_i
      assert_equal 3, persisted.fetch('impact').to_i
      html = JrcServiceDesk::Glpi::Content.rich(persisted.fetch('content'), from_source: true)
      assert_includes html, '<strong>operator</strong>'
      assert_includes html, '<td>Evidence</td>'
      assert client.collection("Ticket/#{receipt.fetch(:remote_id)}/Ticket_User/").any? { |row| row['type'].to_i == 1 && row['users_id'].to_i == requester }
    end
    GlpiLabEvidence::CHECKS << 'actual explicit model, edited values, hidden predefined urgency, rich content, requester and one idempotent write'
  end

  def test_actual_required_placeholder_hidden_unsupported_and_foreign_models_block_every_item_write
    model = @fixtures.fetch('models').fetch('explicit')
    requester = @fixtures.fetch('users').fetch('base').fetch('id')
    valid = { 'template_id' => model, 'name' => 'Synthetic blocked model', 'content' => 'Real changed issue', '_users_id_requester' => requester }
    cases = [
      [valid.except('_users_id_requester'), 'required_fields_missing'],
      [valid.except('content').merge('template_id' => @fixtures.fetch('models').fetch('entity')), 'required_fields_missing'],
      [valid.merge('content' => '<p>Describe the synthetic issue</p>', 'content_format' => 'rich'), 'required_content_unchanged'],
      [valid.merge('urgency' => 5), 'hidden_field_override'],
      [valid.merge('template_id' => @fixtures.fetch('models').fetch('unsupported')), 'template_fields_unsupported'],
      [valid.merge('template_id' => @fixtures.fetch('models').fetch('foreign')), 'not_authorized']
    ]
    source do |client|
      unsupported = ticket_form(client, 'template_id' => @fixtures.fetch('models').fetch('unsupported'))
      refute unsupported.fetch(:supported)
      assert_includes unsupported.fetch(:unsupported_required), 'requesttypes_id'
    end
    cases.each do |attributes, error|
      before = GlpiLabTransport::ITEM_MUTATIONS.dup
      receipt = create(attributes)
      assert_equal 'rejected', receipt.fetch(:state), receipt.inspect
      assert_equal error, receipt.fetch(:error_code)
      assert_equal before, GlpiLabTransport::ITEM_MUTATIONS
    end
    GlpiLabEvidence::CHECKS << 'actual required requester, unchanged rich placeholder, hidden override, unsupported source requirement and foreign template: zero item writes'
  end

  def test_actual_denied_template_metadata_is_a_source_403_and_never_falls_back_or_writes
    @connection.update!(user_token: @fixtures.fetch('users').fetch('denied').fetch('token'))
    before = GlpiLabTransport::ITEM_MUTATIONS.dup
    source do |client|
      profile = client.get('getActiveProfile/').fetch('active_profile')
      assert_operator profile.fetch('ticket').to_i & 4, :>, 0
      assert_equal 0, profile.fetch('itiltemplate').to_i
      error = assert_raises(JrcServiceDesk::Glpi::Error) { ticket_form(client) }
      assert_equal 403, error.http_status
      assert_equal 'ERROR_RIGHT_MISSING', error.code
    end
    receipt = create({ 'name' => 'Synthetic denied metadata', 'content' => 'Synthetic source refusal' })
    assert_equal 'rejected', receipt.fetch(:state)
    assert_equal 'ERROR_RIGHT_MISSING', receipt.fetch(:error_code)
    assert_equal before, GlpiLabTransport::ITEM_MUTATIONS
    GlpiLabEvidence::CHECKS << 'actual profile can create tickets but template metadata403 blocks form and action with zero item writes'
  end

  def test_actual_source_policy_drift_rejects_stale_form_before_ticket_write
    model = @fixtures.fetch('models').fetch('profile')
    form = source { |client| ticket_form(client, 'template_id' => model) }
    rule = @fixtures.fetch('predefined_ids').fetch('profile_urgency')
    original = nil
    begin
      source do |client|
        original = client.get("TicketTemplatePredefinedField/#{rule}").fetch('value')
        client.update_item('TicketTemplatePredefinedField', rule, 'value' => '2')
        assert_equal '2', client.get("TicketTemplatePredefinedField/#{rule}").fetch('value')
        refute_equal form.fetch(:version), ticket_form(client, 'template_id' => model).fetch(:version)
      end
      before = GlpiLabTransport::ITEM_MUTATIONS.dup
      receipt = create({ 'template_id' => model, 'content' => 'Synthetic stale form' }, template_version: form.fetch(:version))
      assert_equal 'rejected', receipt.fetch(:state)
      assert_equal 'template_changed', receipt.fetch(:error_code)
      assert_equal before, GlpiLabTransport::ITEM_MUTATIONS
    ensure
      source { |client| client.update_item('TicketTemplatePredefinedField', rule, 'value' => original) } if original
    end
    GlpiLabEvidence::CHECKS << 'actual persisted source template edit invalidates version and prevents every item write'
  end

  private

  def access
    JrcServiceDesk::Glpi::Access.new(@identity)
  end

  def source(&block)
    JrcServiceDesk::Glpi::Client.new(@connection).session(&block)
  end

  def ticket_form(client, filters = {})
    JrcServiceDesk::Glpi::TicketForm.new.call(access: access, client: client, filters: { 'entity_id' => @entity }.merge(filters))
  end

  def create(attributes, template_version: nil, idempotency_key: SecureRandom.uuid)
    @executor.call(access: access, operation: 'ticket.create', target_id: nil, entity_id: @entity,
      attributes: attributes, idempotency_key: idempotency_key, template_version: template_version)
  end
end
