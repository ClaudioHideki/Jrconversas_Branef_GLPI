class JrcDomainCommands::Scope
  def initialize(authority)
    @authority = authority
    @account = authority.account
  end

  def authorize!(input, command: nil)
    authorize_actor!(command)
    validate_identity!(input)
    binding = binding!(input)
    @account.inboxes.lock('FOR SHARE').find(binding.inbox_id)
  end

  def owners
    return [] unless crm?

    members = @account.account_users.includes(:user).order(:id).limit(201).to_a
    raise ArgumentError, 'domain_owner_directory_bound' if members.size > 200

    members.filter_map do |member|
      next unless JrcOperations::Access.crm?(member) && member.user.active_for_authentication? && member.user.confirmed?

      { id: member.user_id, name: member.user.name.to_s.first(160) }
    end
  end

  def commands(inbox:, intake_protocol: nil)
    available = crm? ? JrcDomainCommands::Request::COMMANDS.dup : []
    configuration = JrcServiceDesk::IntakeConfiguration.find_by(account_id: @account.id, inbox_id: inbox.id, current: true, enabled: true)
    available += JrcDomainCommands::Request::INTAKE_COMMANDS if intake_protocol == '1' && service_desk? && configuration
    available
  end

  private

  def authorize_actor!(command)
    raise Pundit::NotAuthorizedError unless JrcBroker::Configuration.enabled? && @account.feature_enabled?('jrc_broker')

    member = @account.account_users.lock('FOR SHARE').find_by!(user_id: @authority.user.id)
    CustomRole.lock('FOR SHARE').find(member.custom_role_id) if member.custom_role_id
    raise Pundit::NotAuthorizedError unless allowed_command?(command)
  end

  def allowed_command?(command)
    return crm? || service_desk? if command.nil?
    return service_desk? if JrcDomainCommands::Request::INTAKE_COMMANDS.include?(command)

    JrcDomainCommands::Request::COMMANDS.include?(command) && crm?
  end

  def crm?
    member = @account.account_users.find_by(user_id: @authority.user.id)
    JrcOperations::Access.crm?(member)
  end

  def service_desk?
    context = JrcServiceDesk::OperationalContext.new(account: @account, user: @authority.user,
      account_user: @account.account_users.find_by(user_id: @authority.user.id))
    context.native_operator? && context.capability?(:tickets_create)
  end

  def validate_identity!(input)
    valid = %w[organization_id integration_id].all? { |key| JrcFlowEffects::Request::UUID.match?(input[key].to_s) }
    raise ArgumentError, 'domain_identity' unless valid
  end

  def binding!(input)
    integration = JrcBrokerIntegration.lock('FOR SHARE').find_by!(account_id: @account.id)
    binding = JrcBrokerInboxBinding.lock('FOR SHARE').find_by!(account_id: @account.id,
                                                               inbox_id: JrcFlowEffects::Request.integer(input['inbox_id']))
    unless integration.organization_id == input.fetch('organization_id') && binding.integration_id == input.fetch('integration_id')
      raise ArgumentError, 'domain_binding'
    end

    binding
  end
end
