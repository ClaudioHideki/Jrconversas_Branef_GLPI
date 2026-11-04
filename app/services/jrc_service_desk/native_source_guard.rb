# frozen_string_literal: true

class JrcServiceDesk::NativeSourceGuard
  def self.selected_glpi?(account)
    JrcServiceDesk::GlpiConnection.exists?(account_id: account.id, primary_source: true)
  end

  def self.call(user_context)
    context = JrcServiceDesk::OperationalContext.new(user_context)
    raise Pundit::NotAuthorizedError unless context.native_operator?
    raise JrcServiceDesk::Glpi::Error.new('glpi_source_required', 409) if selected_glpi?(context.account)

    context
  end
end
