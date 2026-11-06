# frozen_string_literal: true

class JrcServiceDesk::Intake::NoticePolicy
  def initialize(demand, actor)
    @demand = demand
    @actor = actor
  end

  def context
    JrcServiceDesk::OperationalContext.new(account: @demand.account, user: @actor.user, account_user: @actor)
  end

  def authorize!
    native = context
    raise Pundit::NotAuthorizedError unless native.native_operator? && native.capability?(:notifications_manage)

    access = JrcServiceDesk::Glpi::Access.new(native.to_h).ready!
    mapping = JrcServiceDesk::Intake::Mapping.new(@demand)
    unit = native.unit_scope.find(access.unit_for(mapping.route.fetch('entity_id')))
    raise Pundit::NotAuthorizedError unless native.operational_unit_allowed?(unit)

    JrcServiceDesk::NativeExecutionContext.with(native.to_h) do
      raise Pundit::NotAuthorizedError unless ConversationPolicy.new(native.to_h, @demand.conversation).show?
    end
    native
  end

  def blocker
    authorize!
    return 'notifications_disabled' unless configuration.enabled? && configuration.remote_writes_enabled? && settings['enabled'] == true
    return 'notification_owner_unconfigured' unless settings['owner'] == 'jrc'
    return 'intake_not_delivered' unless %w[confirmed partial].include?(@demand.state) && @demand.remote_id
    return 'channel_unavailable' unless settings['channel'] == 'whatsapp' && channel_ready?
    return 'recipient_blocked' if conversation.contact.blocked?
    return 'recipient_preference' unless JrcServiceDesk::ContactNotificationPreferences.channels(conversation.contact).include?('whatsapp')
    return 'recipient_missing' if conversation.contact.phone_number.blank?

    nil
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcServiceDesk::Glpi::Error, ArgumentError, KeyError
    'notification_not_authorized'
  end

  def recipient_digest
    JrcServiceDesk::CanonicalJson.digest(account_id: @demand.account_id, inbox_id: @demand.inbox_id,
      contact_id: @demand.contact_id, recipient: conversation.contact.phone_number)
  end

  def configuration = @demand.intake_configuration.reload
  def settings = configuration.mappings.fetch('notifications', {})

  private

  def conversation = @demand.conversation.reload

  def channel_ready?
    JrcServiceDesk::NotificationEngine.channel(conversation.inbox) == 'whatsapp' && conversation.can_reply?
  end
end
