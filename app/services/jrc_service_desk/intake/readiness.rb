# frozen_string_literal: true

class JrcServiceDesk::Intake::Readiness
  KEYS = %w[inbox_id catalogue responses mappings mode remote_writes_enabled].freeze
  attr_reader :configuration, :context

  def call(user_context:, attributes:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    authorize!
    values = JrcServiceDesk::Input.attributes(attributes, KEYS)
    @configuration = build_configuration(values)
    raise ArgumentError, 'intake_configuration_invalid' unless configuration.valid?

    @selections = JrcServiceDesk::Intake::SelectionSet.new(configuration.catalogue).rows
    @blockers = []
    @candidates = @selections.filter_map { |selection| candidate(selection) }
    verify_source if @blockers.empty?
    { ready: @blockers.empty?, blockers: @blockers.uniq, selection_count: @selections.size,
      checked_at: Time.current.iso8601, requester_policy: 'mapped_contacts_only' }
  end

  private

  def authorize!
    valid = context.administrator? && context.capability?(:settings_view) && context.user&.confirmed? &&
            context.user.active_for_authentication? && context.account.active?
    raise Pundit::NotAuthorizedError unless valid
  end

  def build_configuration(values)
    inbox = context.account.inboxes.find(JrcServiceDesk::Input.id(values.fetch('inbox_id')))
    JrcServiceDesk::IntakeConfiguration.new(
      account: context.account, inbox: inbox, created_by_account_user: context.account_user,
      revision: (JrcServiceDesk::IntakeConfiguration.where(account: context.account, inbox: inbox).maximum(:revision) || 0) + 1,
      catalogue: values.fetch('catalogue'), responses: values.fetch('responses'), mappings: values.fetch('mappings'),
      mode: values.fetch('mode'), enabled: true, current: false, remote_writes_enabled: false
    )
  end

  def candidate(selection)
    rows = configuration.mappings.fetch('routes', []).select do |row|
      JrcServiceDesk::Intake::Mapping::SELECTORS.all? { |key| row[key] == selection[key] }
    end
    raise ArgumentError, 'intake_route_unmapped' unless rows.one?

    route = rows.first
    validate_sla!(route, selection)
    requester = requester!(route)
    [selection, requester]
  rescue ArgumentError, KeyError, ActiveRecord::RecordNotFound => e
    @blockers << (e.is_a?(ArgumentError) && e.message.start_with?('intake_') ? e.message : 'intake_mapping_invalid')
    nil
  end

  def validate_sla!(route, selection)
    return if selection.fetch('sla').fetch('unit') == 'none' && route['sla'].nil?

    sla = route.fetch('sla', {})
    raise ArgumentError, 'intake_sla_unmapped' unless sla.is_a?(Hash) && %w[id purpose calendar_id].all? { |key| sla.key?(key) }
  end

  def requester!(route)
    raise ArgumentError, 'intake_requester_unmapped' unless route['requester_policy'] == 'mapped_contact'

    rows = configuration.mappings.fetch('requesters', []).select { |row| row['entity_id'].to_s == route.fetch('entity_id').to_s }
    raise ArgumentError, 'intake_requester_unmapped' if rows.empty?

    rows.each { |row| context.account.contacts.find(JrcServiceDesk::Input.id(row.fetch('contact_id'))) }
    rows
  end

  def verify_source
    JrcServiceDesk::Intake::ReadinessSource.new(context, configuration).call(@candidates)
  rescue JrcServiceDesk::Glpi::Error => e
    @blockers << e.code
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    @blockers << 'intake_source_not_authorized'
  rescue ArgumentError, KeyError, TypeError
    @blockers << 'intake_mapping_invalid'
  end
end
