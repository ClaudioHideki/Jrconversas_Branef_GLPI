require Rails.root.join('app/middleware/jrc_glpi_sentiment_timeout')

# This application's rack-timeout gem is enabled only in the production group.
Rails.application.config.middleware.swap Rack::Timeout, JrcGlpiSentimentTimeout if Rails.env.production?
