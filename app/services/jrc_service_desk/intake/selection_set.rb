# frozen_string_literal: true

# Bounded expansion for configuration coverage, never an authority or a customer lookup.
class JrcServiceDesk::Intake::SelectionSet
  def initialize(catalogue)
    @catalogue = JrcServiceDesk::Intake::Catalogue.new(catalogue)
  end

  def rows
    values = []
    @catalogue.document.fetch('systems').each do |system|
      system.fetch('reasons').each do |reason|
        combinations(system, reason).each do |location, profile, subject, severity|
          values << @catalogue.classify(system: system['code'], location: location['code'], profile: profile&.fetch('code'),
                                       reason: reason['code'], subject: subject['code'], severity: severity)
          raise ArgumentError, 'intake_selection_limit' if values.size > 1000
        end
      end
    end
    values
  end

  private

  def combinations(system, reason)
    profiles = system.fetch('profiles').presence || [nil]
    severities = reason.fetch('sla').key?('by_severity') ? JrcServiceDesk::Intake::Catalogue::SEVERITIES : [nil]
    system.fetch('locations').product(profiles, reason.fetch('subjects'), severities)
  end
end
