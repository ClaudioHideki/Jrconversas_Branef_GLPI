# frozen_string_literal: true

require 'uri'

# E-mail is a routing hint, never proof of a visitor's identity or permission.
class JrcServiceDesk::Intake::Requester
  def resolve!(access:, client:, entity_id:, email:, policy:)
    unless %w[email_only email_or_anonymous].include?(policy) && email.is_a?(String) &&
           email.length <= 254 && email.match?(URI::MailTo::EMAIL_REGEXP)
      raise ArgumentError, 'intake_requester_policy_invalid'
    end
    field = email_field(client)

    scope = JrcServiceDesk::Glpi::MetadataScope.new(access: access, client: client, entity_id: entity_id)
    parameters = { 'criteria' => [{ 'field' => field.to_i, 'searchtype' => 'equals', 'value' => email }],
                   'forcedisplay' => [2, field.to_i], 'is_deleted' => 0 }
    matches = client.collection('search/User/', parameters).filter_map do |row|
      id = JrcServiceDesk::Input.id(row.fetch('2'))
      emails = client.collection("User/#{id}/UserEmail/")
      next unless emails.any? { |entry| entry['users_id'].to_s == id.to_s && entry['email'].to_s.casecmp?(email) }

      begin
        user = client.get("User/#{id}")
        raise JrcServiceDesk::Glpi::Error.new('invalid_response') unless user['id'].to_s == id.to_s

        scope.authorize!('User', user)
        id
      rescue Pundit::NotAuthorizedError
        nil
      end
    end.uniq
    raise ArgumentError, 'intake_requester_ambiguous' if matches.size > 1
    return { '_users_id_requester' => matches.first } if matches.one?
    raise ArgumentError, 'intake_requester_unmapped' unless policy == 'email_or_anonymous'

    { '_users_id_requester' => 0, '_users_id_requester_notif' => {
      'use_notification' => [1], 'alternative_email' => [email] } }
  end

  def email_field(client)
    options = client.get('listSearchOptions/User/')
    field = options.find do |key, row|
      key.to_s.match?(/\A[1-9]\d*\z/) && row.is_a?(Hash) && row['table'] == 'glpi_useremails' && row['field'] == 'email'
    end&.first
    raise JrcServiceDesk::Glpi::Error.new('intake_email_search_unavailable', 422) unless field

    field
  end
end
