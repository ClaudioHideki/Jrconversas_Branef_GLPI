# frozen_string_literal: true

class JrcServiceDesk::Glpi::LinkedReferences
  def call(user_context:, conversation_id: nil, incident_id: nil, page: 1)
    raise ArgumentError unless conversation_id.nil? != incident_id.nil?

    context = JrcServiceDesk::OperationalContext.new(user_context)
    model = conversation_id ? Conversation : JrcServiceDesk::Incident
    local = model.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(conversation_id || incident_id))
    Pundit.authorize(context.to_h, local, :show?)
    page = JrcServiceDesk::Input.id(page)
    key = conversation_id ? { conversation_id: local.id } : { incident_id: local.id }
    scope = JrcServiceDesk::GlpiReferenceLink.where(account_id: context.account.id, **key)
      .where(unit_id: context.view_unit_scope.select(:id)).includes(:glpi_reference).order(:id)
    rows = scope.offset((page - 1) * 25).limit(26).to_a
    items = []
    errors = []
    if rows.any?
      begin
        access = JrcServiceDesk::Glpi::Access.new(context.to_h).ready!
        JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
          rows.first(25).each do |link|
            begin
              ref = JrcServiceDesk::Glpi::Reference.new(link.glpi_reference.reference)
              ref.authorize!(access: access, client: client)
              items << { link_id: link.id.to_s, reference_record_id: link.glpi_reference_id, reference: ref.values }
            rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
              errors << 'not_authorized'
            rescue JrcServiceDesk::Glpi::Error => error
              errors << error.code
            end
          end
        end
      rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
        errors << 'not_authorized'
      rescue JrcServiceDesk::Glpi::Error => error
        errors << error.code
      end
    end
    { items: items, meta: { page: page, per_page: 25, next_page: rows.size > 25 ? page + 1 : nil },
      coverage: { complete: errors.empty? && rows.size <= 25, errors: errors.tally, source: 'glpi', observed_at: Time.current.iso8601 } }
  end
end
