# frozen_string_literal: true

require_relative 'glpi_source_fixture'

class IntakeGlpiSource < GlpiCommandSource
  attr_accessor :fail_assignment, :fail_after_create

  def collection(path, *)
    actors = super
    if path.match?(%r{\ATicket/\d+/Ticket_User/\z})
      id = path.split('/')[1].to_i
      requester = rows.fetch("Ticket/#{id}", {})['_users_id_requester']
      actors += [{ 'id' => 2, 'tickets_id' => id, 'users_id' => requester, 'type' => 1 }] if requester
    end
    actors
  end

  def write!(verb, type, id, input)
    if assignment_failed?(verb, type, input)
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403)
    end

    result = super
    raise JrcServiceDesk::Glpi::Error.new('transport_timeout', 502) if fail_after_create && type == 'Ticket' && verb == :post

    result
  end

  def assignment_failed?(verb, type, input)
    fail_assignment && type == 'Ticket' && verb == :patch && input.key?('_groups_id_assign')
  end
end

