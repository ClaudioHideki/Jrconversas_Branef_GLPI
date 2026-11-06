# frozen_string_literal: true

# Shared synthetic fixture for intake integration tests. No customer data or endpoints.
raise 'Wrong validation target' unless ENV['RAILS_ENV'] == 'test' && ENV['POSTGRES_DATABASE'] == 'branef_glpi_test'

require 'base64'
require 'securerandom'
ENV['JRC_BROKER_CREDENTIAL_KEY'] = Base64.strict_encode64(SecureRandom.random_bytes(32))
ENV['JRC_BROKER_ALLOWED_ORIGINS'] = 'https://broker.example.test'
require_relative 'glpi_test_helper'

class IntakeIntegrationTest < GlpiIntegrationTest
  def setup
    super
    channel = Channel::Api.create!(account: @account)
    @inbox = Inbox.create!(account: @account, channel: channel, name: 'Synthetic intake')
    contact = Contact.create!(account: @account, name: 'Synthetic requester')
    contact_inbox = ContactInbox.create!(contact: contact, inbox: @inbox, source_id: SecureRandom.uuid)
    @conversation = Conversation.create!(account: @account, inbox: @inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)
    configure_intake
    @access_token = AccessToken.find_or_create_by!(owner: @user)
    @authority = JrcFlowEffects::Authority.new(account: @account, user: @user, access_token: @access_token)
    configure_broker
    @arguments = { 'configuration_id' => @configuration.id, 'configuration_revision' => 1,
                   'episode_key' => SecureRandom.uuid, 'phase' => 'qualified', 'input' => {
                     'system' => 'example', 'location' => 'south', 'reason' => 'request', 'subject' => 'access',
                     'profile' => 'requester', 'identifier' => '12345678901', 'email' => 'synthetic@example.invalid',
                     'description' => 'Synthetic support request'
                   } }
  end

  private

  def configure_intake
    @catalogue = JSON.parse(File.read(File.join(__dir__, 'fixtures/intake_catalogue.json')))
    @configuration = JrcServiceDesk::IntakeConfiguration.create!(
      account: @account, inbox: @inbox, created_by_account_user: @member, revision: 1, catalogue: @catalogue, mode: 'on_handoff',
      enabled: true, remote_writes_enabled: false, current: true
    )
  end

  def configure_broker
    @account.enable_features!('jrc_broker')
    @organization = SecureRandom.uuid
    @integration = SecureRandom.uuid
    JrcBrokerIntegration.create!(account: @account, organization_id: @organization, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    @binding = JrcBrokerInboxBinding.create!(account: @account, inbox: @inbox, integration_id: @integration, instance_id: SecureRandom.uuid)
  end
end
