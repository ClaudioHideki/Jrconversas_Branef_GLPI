# frozen_string_literal: true

require 'uri'

class JrcServiceDesk::GlpiConnection < JrcServiceDesk::AccountRecord
  encrypts :user_token, support_unencrypted_data: false
  encrypts :app_token, support_unencrypted_data: false
  validates :base_url, :user_token, :app_token, :timezone, presence: true
  validates :account_id, uniqueness: true
  validates :enabled, inclusion: { in: [true, false] }
  validate :configuration_is_valid

  def public_configuration
    attributes.slice('base_url', 'enabled', 'timezone', 'entity_mappings', 'user_mappings', 'categories', 'lock_version').merge(
      'configured' => persisted?, 'user_token_configured' => user_token.present?, 'app_token_configured' => app_token.present?
    )
  end

  private

  def configuration_is_valid
    uri = URI.parse(base_url.to_s)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
           uri.path.delete_suffix('/').end_with?('/apirest.php')
      errors.add(:base_url, 'must be an HTTPS apirest.php endpoint without credentials or query')
    end
    errors.add(:timezone, 'is invalid') unless ActiveSupport::TimeZone[timezone]
    validate_mappings!
  rescue URI::InvalidURIError, ArgumentError, KeyError
    errors.add(:base, 'invalid GLPI configuration')
  end

  def validate_mappings!
    raise ArgumentError unless [entity_mappings, user_mappings, categories].all? { |value| value.is_a?(Array) && value.size <= 500 }

    entities = entity_mappings.map do |row|
      values = JrcServiceDesk::Input.attributes(row, %w[entity_id unit_id])
      id = JrcServiceDesk::Glpi::Identifiers.remote(values.fetch('entity_id'))
      unit = JrcServiceDesk::Unit.where(account_id: account_id, active: true).find(JrcServiceDesk::Input.id(values.fetch('unit_id')))
      raise ArgumentError unless unit.operator_company&.active?

      id
    end
    raise ArgumentError unless entities.uniq == entities

    users = user_mappings.map do |row|
      values = JrcServiceDesk::Input.attributes(row, %w[account_user_id glpi_user_id])
      AccountUser.where(account_id: account_id).find(JrcServiceDesk::Input.id(values.fetch('account_user_id')))
      JrcServiceDesk::Input.id(values.fetch('glpi_user_id'))
      JrcServiceDesk::Input.id(values.fetch('account_user_id'))
    end
    raise ArgumentError unless users.uniq == users

    categories.each do |row|
      values = JrcServiceDesk::Input.attributes(row, %w[id name entity_id])
      JrcServiceDesk::Input.id(values.fetch('id'))
      raise ArgumentError unless entities.include?(JrcServiceDesk::Glpi::Identifiers.remote(values.fetch('entity_id')))
      raise ArgumentError unless values.fetch('name').is_a?(String) && values['name'].length.between?(1, 255)
    end
  rescue ActiveRecord::RecordNotFound
    errors.add(:base, 'mappings must reference active records in this account')
  end
end
