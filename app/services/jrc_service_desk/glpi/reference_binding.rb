# frozen_string_literal: true

# The headers are preconditions against a server-selected connection, never a
# selector for an account or source. A remote numeric ID alone is ambiguous.
class JrcServiceDesk::Glpi::ReferenceBinding
  def self.verify!(access:, connection_id:, connection_version:, required:)
    return true if !required && connection_id.nil? && connection_version.nil?

    if connection_id.nil? || connection_version.nil?
      raise JrcServiceDesk::Glpi::Error.new('configuration_precondition_required', 409)
    end

    connection = access.connection
    matches = connection && connection_id.to_s.match?(/\A[1-9]\d*\z/) &&
              connection_version.to_s.match?(/\A(?:0|[1-9]\d*)\z/) &&
              connection_id.to_s == connection.id.to_s && connection_version.to_s == connection.lock_version.to_s
    raise JrcServiceDesk::Glpi::Error.new('configuration_changed', 409) unless matches

    true
  end
end
