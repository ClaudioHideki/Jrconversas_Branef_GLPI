# frozen_string_literal: true

class JrcServiceDesk::Glpi::Capabilities
  def call(access:, client:)
    access.ready!
    profile = client.get('getActiveProfile/').fetch('active_profile')
    operations = JrcServiceDesk::Glpi::OperationCatalogue::OPERATIONS.map do |name, descriptor|
      right, mask = descriptor.fetch(:source_right)
      checked = profile.key?(right) && profile[right].to_s.match?(/\A\d+\z/)
      local = access.context.capability?(descriptor.fetch(:capability).to_sym) &&
        (!descriptor.fetch(:admin) || access.context.administrator?)
      { operation: name, itemtype: descriptor.fetch(:type), verb: descriptor.fetch(:verb), supported: true,
        permitted: local, source_checked: checked, source_allowed: checked ? (profile[right].to_i & mask).positive? : nil,
        source_check_scope: 'profile', requires_item_check: true, homologated: false,
        fields: descriptor.fetch(:fields), required: descriptor.fetch(:required), parent: descriptor[:parent] }
    end
    { operations: operations, profile: profile.slice('id', 'name'), technical_identity: true }
  end
end
