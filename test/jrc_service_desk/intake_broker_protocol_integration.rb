# frozen_string_literal: true

require_relative 'intake_test_helper'

class IntakeBrokerProtocolIntegrationTest < IntakeIntegrationTest
  def setup
    super
    @domain = @arguments.merge('command' => 'service_desk_intake')
  end

  def test_intake_domain_receipt_is_durable_without_remote_io_or_conversation_takeover
    before = @conversation.reload.attributes
    JrcServiceDesk::Glpi::Client.stub(:new, ->(*) { flunk 'The Flow transaction cannot request GLPI' }) do
      result = apply(@domain).domain_result
      assert_equal 'JrcServiceDesk::IntakeDemand', result.fetch('resource_type')
      assert_equal 'test_only', result.dig('intake', 'state')
      assert_nil result.dig('intake', 'remote_id')
      refute_includes result.to_json, @arguments.dig('input', 'identifier')
      refute_includes result.to_json, @arguments.dig('input', 'email')
    end
    assert_equal before, @conversation.reload.attributes
    assert_equal 1, JrcServiceDesk::IntakeDemand.where(account: @account).count
  end

  def test_status_reads_the_same_episode_without_creating_another_demand
    initial = apply(@domain).domain_result
    result = apply('command' => 'service_desk_status', 'episode_key' => @arguments.fetch('episode_key')).domain_result
    assert_equal initial.fetch('resource_id'), result.fetch('resource_id')
    assert_equal false, result.fetch('created')
    assert_equal 1, JrcServiceDesk::IntakeDemand.where(account: @account).count
  end

  def test_status_cannot_read_an_episode_from_another_conversation
    apply(@domain)
    channel = Channel::Api.create!(account: @account)
    foreign = Inbox.create!(account: @account, channel: channel, name: 'Other scoped inbox')
    route = ContactInbox.create!(contact: @conversation.contact, inbox: foreign, source_id: SecureRandom.uuid)
    other = Conversation.create!(account: @account, inbox: foreign, contact: @conversation.contact, contact_inbox: route, status: :pending)
    @binding.update!(inbox: foreign)
    assert_raises(ActiveRecord::RecordNotFound) do
      apply({ 'command' => 'service_desk_status', 'episode_key' => @arguments.fetch('episode_key') }, conversation: other)
    end
  end

  def test_new_commands_are_only_advertised_to_an_opted_in_client
    http = ActionDispatch::Integration::Session.new(Rails.application)
    url = "/api/v1/accounts/#{@account.id}/jrc_domain_commands/capabilities"
    params = { inbox_id: @inbox.id, organization_id: @organization, integration_id: @integration }
    headers = { 'api_access_token' => @access_token.token }
    http.get(url, params: params, headers: headers)
    assert_equal 200, http.response.status
    refute_includes JSON.parse(http.response.body).fetch('commands'), 'service_desk_intake'
    http.get(url, params: params.merge(intake_protocol: '1'), headers: headers)
    assert_equal 200, http.response.status
    assert_includes JSON.parse(http.response.body).fetch('commands'), 'service_desk_intake'
  end

  private

  def apply(arguments, conversation: @conversation)
    input = { 'organization_id' => @organization, 'integration_id' => @integration,
      'operation_id' => SecureRandom.uuid, 'dispatch_proof' => SecureRandom.uuid, 'inbox_id' => conversation.inbox_id.to_s,
      'remote_contact_id' => conversation.contact_id.to_s,
      'expected_control_revision' => conversation.reload.jrc_effect_control_revision.to_s,
      'operation' => 'domain', 'value_json' => JSON.generate(arguments) }
    JrcFlowEffects::Apply.new(account: @account, user: @user, access_token: @access_token).call(conversation.display_id, input)
  end
end
