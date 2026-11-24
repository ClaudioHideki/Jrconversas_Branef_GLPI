require Rails.root.join('app/middleware/jrc_glpi_sentiment_timeout')

Rails.application.config.middleware.swap Rack::Timeout, JrcGlpiSentimentTimeout
