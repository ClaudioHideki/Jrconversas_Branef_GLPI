require Rails.root.join('app/middleware/jrc_glpi_sentiment_timeout')

# rack-timeout deliberately omits its Rails middleware in the test environment.
Rails.application.config.middleware.swap Rack::Timeout, JrcGlpiSentimentTimeout unless Rails.env.test?
