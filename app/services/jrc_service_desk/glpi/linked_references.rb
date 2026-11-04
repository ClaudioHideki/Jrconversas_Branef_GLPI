# frozen_string_literal: true

class JrcServiceDesk::Glpi::LinkedReferences
  def call(user_context:, conversation_id: nil, incident_id: nil, page: 1)
    raise ArgumentError unless conversation_id.nil? != incident_id.nil?

    context = JrcServiceDesk::OperationalContext.new(user_context)
    raise Pundit::NotAuthorizedError unless context.account && context.user && context.account_user
    model = conversation_id ? Conversation : JrcServiceDesk::Incident
    local = model.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(conversation_id || incident_id))
    Pundit.authorize(context.to_h, local, :show?)
    page = JrcServiceDesk::Input.id(page)
    key = conversation_id ? { conversation_id: local.id } : { incident_id: local.id }
    rows = JrcServiceDesk::GlpiReferenceLink.where(account_id: context.account.id, **key).includes(:glpi_reference).order(:id)
    items = []
    errors = []
    visible = 0
    more = false
    if rows.exists?
      begin
        access = JrcServiceDesk::Glpi::Access.new(context.to_h).ready!
        JrcServiceDesk::Glpi::Client.new(access.connection).session do |client|
          rows.each do |link|
            begin
              ref = JrcServiceDesk::Glpi::Reference.new(link.glpi_reference.reference)
              ref.authorize!(access: access, client: client)
              visible += 1
              next if visible <= (page - 1) * 25
              if items.size == 25
                more = true
                break
              end
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
    { items: items, meta: { page: page, per_page: 25, next_page: more ? page + 1 : nil },
      coverage: { complete: errors.empty? && !more, errors: errors.uniq.tally, source: 'glpi', observed_at: Time.current.iso8601 } }
  end
end
