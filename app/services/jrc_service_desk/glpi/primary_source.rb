# frozen_string_literal: true

class JrcServiceDesk::Glpi::PrimarySource
  def self.for(user_context)
    context = JrcServiceDesk::OperationalContext.new(user_context)
    return 'native' unless context.available?

    connection = JrcServiceDesk::GlpiConnection.find_by(account_id: context.account.id)
    connection&.primary_source? ? 'glpi' : 'native'
  end
end
