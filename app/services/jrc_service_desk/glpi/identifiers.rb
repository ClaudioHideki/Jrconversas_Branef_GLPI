# frozen_string_literal: true

module JrcServiceDesk::Glpi::Identifiers
  def self.remote(value)
    return 0 if value == 0 || value == '0'

    JrcServiceDesk::Input.id(value)
  end
end
