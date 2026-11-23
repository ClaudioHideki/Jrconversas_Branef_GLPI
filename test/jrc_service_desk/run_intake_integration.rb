# frozen_string_literal: true

Dir[File.join(__dir__, 'intake_*_integration.rb')].each { |path| require path }
require_relative 'glpi_ticket_form_integration'
