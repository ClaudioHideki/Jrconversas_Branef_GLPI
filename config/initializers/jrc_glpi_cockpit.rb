# Branef extension only. Resolve by name on each call to support Rails reloads.
Rails.application.config.x[:jrc_cockpit_ticket_metrics_provider] = 'JrcServiceDesk::Glpi::CockpitMetrics'
