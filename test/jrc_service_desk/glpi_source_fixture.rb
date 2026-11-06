# frozen_string_literal: true

# Synthetic GLPI state, behind the real command service; never connects to a server.
class GlpiCommandSource
  attr_accessor :failure, :on_profile, :ignore_write, :denied, :skip_solution_status, :confirmation_error
  attr_reader :writes, :rows

  def initialize
    @writes = []
    @rows = { 'Ticket/101' => { 'id' => 101, 'entities_id' => 0, 'date_mod' => 'v1', 'type' => 1 },
      'Problem/201' => { 'id' => 201, 'entities_id' => 0, 'date_mod' => 'v1' },
      'Change/301' => { 'id' => 301, 'entities_id' => 0, 'date_mod' => 'v1' },
      'Entity/0' => { 'id' => 0, 'entities_id' => nil, 'tickettype' => 1, 'tickettemplates_strategy' => 0, 'tickettemplates_id' => 0 } }
  end

  def session(**)
    yield self
  end

  def get(path, *)
    if path == 'getActiveProfile/'
      on_profile&.call
      profile = %w[ticket followup task ticketvalidation changevalidation problem change knowbase itilcategory itiltemplate].to_h { |key| [key, denied ? 0 : 1048575] }
      return { 'active_profile' => profile.merge('id' => 6, 'tickettemplates_id' => 0) }
    end
    return { '1' => { 'table' => 'glpi_tickets', 'field' => 'name' },
      '21' => { 'table' => 'glpi_tickets', 'field' => 'content' }, '14' => { 'table' => 'glpi_tickets', 'field' => 'type' },
      '10' => { 'table' => 'glpi_tickets', 'field' => 'urgency' }, '11' => { 'table' => 'glpi_tickets', 'field' => 'impact' },
      '3' => { 'table' => 'glpi_tickets', 'field' => 'priority' }, '12' => { 'table' => 'glpi_tickets', 'field' => 'status' },
      '7' => { 'table' => 'glpi_itilcategories', 'field' => 'completename' } } if path == 'listSearchOptions/Ticket/'
    return { 'session' => { 'glpiID' => 900 } } if path == 'getFullSession/'
    return { 'myentities' => [{ 'id' => 0, 'name' => 'Synthetic root' }] } if path == 'getMyEntities/'
    return { 'totalcount' => 1, 'data' => [{ '2' => 101, '1' => 'Synthetic', '80' => 'Root' }] } if path == 'search/Ticket/'
    if confirmation_error && writes.any? && path == "#{writes.last[1]}/#{writes.last[2] || 501}"
      raise JrcServiceDesk::Glpi::Error.new(confirmation_error, 403)
    end
    row = rows[path]
    raise JrcServiceDesk::Glpi::Error.new('ERROR_ITEM_NOT_FOUND', 404) unless row

    row.deep_dup
  end

  def collection(path, *)
    return [{ 'id' => 1, 'knowbaseitems_id' => 501, 'entities_id' => 0 }] if path == 'KnowbaseItem/501/Entity_KnowbaseItem/'
    return [{ 'id' => 1, 'users_id' => 77, 'entities_id' => 0 }] if path == 'User/77/Profile_User/'
    if path.match?(%r{\A(?:Ticket|Problem|Change)/\d+/(?:Ticket_User|Group_Ticket|Problem_User|Group_Problem|Change_User|Change_Group)/\z})
      type, id, relation = path.split('/')
      row = rows["#{type}/#{id}"] || {}
      key = relation.include?('Group') ? 'groups_id' : 'users_id'
      value = row[key == 'groups_id' ? '_groups_id_assign' : '_users_id_assign']
      return value ? [{ 'id' => 1, "#{type.downcase}s_id" => id.to_i, key => value, 'type' => 2 }] : []
    end

    []
  end

  def create_item(type, input)
    write!(:post, type, nil, input)
  end

  def update_item(type, id, input)
    write!(:patch, type, id, input)
  end

  def delete_item(type, id, **)
    write!(:delete, type, id, {})
  end

  def write!(verb, type, id, input)
    raise JrcServiceDesk::Glpi::Error.new('ERROR_RESOURCE_NOT_FOUND', 404) if type == 'Problem_Group'
    raise 'Intent was not durable before sending' unless JrcServiceDesk::GlpiCommand.where(state: 'sending').exists?

    writes << [verb, type, id, input.deep_dup]
    raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403) if failure == 'ERROR_RIGHT_MISSING'
    id ||= 501
    unless ignore_write
      if verb == :delete
        rows.delete("#{type}/#{id}")
      else
        rows["#{type}/#{id}"] = (rows["#{type}/#{id}"] || {}).merge(input).merge('id' => id, 'date_mod' => 'v2')
        if type == 'ITILSolution' && !skip_solution_status
          rows["#{input.fetch('itemtype')}/#{input.fetch('items_id')}"]['status'] = 5
        end
      end
    end
    raise JrcServiceDesk::Glpi::Error.new(failure, failure == 'ERROR_RIGHT_MISSING' ? 403 : 502) if failure

    { 'id' => id, 'deleted' => verb == :delete }
  end
end
