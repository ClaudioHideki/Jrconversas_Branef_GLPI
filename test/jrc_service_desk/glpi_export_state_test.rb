# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'active_support/all'
require 'active_record'
require 'pundit'
require 'logger'

module JrcServiceDesk
  module Glpi; end
end

module Rails
  def self.logger
    @logger ||= Logger.new(IO::NULL)
  end
end

require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/glpi/export'

class GlpiExportStateTest < Minitest::Test
  # The external ORM boundary is in memory here; the actual export lifecycle
  # method runs, including its error handler. The integration suite repeats
  # this scenario with the real receipt and storage.
  class Receipt
    attr_accessor :state, :error_code, :error_http_status

    def initialize
      @state = 'queued'
    end

    def id = 1
    def expires_at = nil
    def with_lock = yield
    def artifact = self
    def purge = nil

    def update!(values)
      @state = values[:state] if values[:state]
    end
  end

  class Service < JrcServiceDesk::Glpi::Export
    def initialize(record)
      @record = record
    end

    private

    def find_record(*) = @record
    def authorize_record(*) = :already_authorized
  end

  def test_premature_download_refuses_file_without_aborting_queued_generation
    record = Receipt.new
    error = assert_raises(JrcServiceDesk::Glpi::Error) { Service.new(record).download(access: nil, id: 1) }
    assert_equal 'export_not_ready', error.code
    assert_equal 409, error.http_status
    assert_equal 'queued', record.state
  end

  def test_background_source403_retains_403_for_nonstandard_error_code
    record = Receipt.new
    record.state = 'failed'
    record.error_code = 'ERROR_LOGIN_FAILED'
    record.error_http_status = 403
    error = assert_raises(JrcServiceDesk::Glpi::Error) { Service.new(record).download(access: nil, id: 1) }
    assert_equal 403, error.http_status
  end
end
