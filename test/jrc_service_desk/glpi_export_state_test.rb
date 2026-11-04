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
    attr_accessor :state, :error_code, :error_http_status, :verification_expires_at, :verification_nonce, :before_lock

    def initialize
      @state = 'queued'
      @attached = true
    end

    def id = 1
    def expires_at = nil
    def with_lock
      callback = @before_lock
      @before_lock = nil
      callback&.call(self)
      yield
    end
    def artifact = self
    def attached? = @attached
    def purge = @attached = false
    def scope = { 'entity_ids' => [7] }
    def source_identity = {}
    def manifest = []
    def total = 1

    def update!(values)
      values.each { |key, value| public_send("#{key}=", value) if respond_to?("#{key}=") }
    end
  end

  class Service < JrcServiceDesk::Glpi::Export
    def initialize(record, source = nil)
      @record = record
      @source = source
    end

    private

    def find_record(*) = @record
    def authorize_record(*) = :already_authorized
    def with_client(*) = yield(@source)
    def audit(*) = nil

    def source_identity(source, *)
      raise JrcServiceDesk::Glpi::Error.new('ERROR_RIGHT_MISSING', 403) if source.revoked

      {}
    end
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

  def test_new_proof_published_after_initial_read_requires_its_own_final_source_probe
    assert_changed_proof_revalidates_source(existing_proof: false)
  end

  def test_replacement_proof_with_identical_expiry_requires_its_own_final_source_probe
    assert_changed_proof_revalidates_source(existing_proof: true)
  end

  def test_continuous_proof_rotation_is_bounded_and_preserves_the_unconsumed_new_proof
    record = Receipt.new
    record.state = 'ready'
    record.verification_nonce = 'first-proof'
    expiry = 30.seconds.from_now
    record.verification_expires_at = expiry
    replacements = %w[second-proof third-proof]
    rotate = lambda do |fresh|
      fresh.verification_nonce = replacements.shift
      fresh.verification_expires_at = expiry
      fresh.before_lock = rotate
    end
    record.before_lock = rotate
    source = Struct.new(:revoked).new(false)
    error = assert_raises(JrcServiceDesk::Glpi::Error) { Service.new(record, source).download(access: nil, id: 1) }
    assert_equal 'export_verification_changed', error.code
    assert_equal 409, error.http_status
    assert_equal 'third-proof', record.verification_nonce
    assert_equal 'ready', record.state
    assert record.artifact.attached?
    assert_empty replacements
  end

  private

  def assert_changed_proof_revalidates_source(existing_proof:)
    record = Receipt.new
    record.state = 'ready'
    expiry = 30.seconds.from_now
    if existing_proof
      record.verification_expires_at = expiry
      record.verification_nonce = 'old-proof'
    end
    source = Struct.new(:revoked).new(false)
    record.before_lock = lambda do |fresh|
      # Another request and its worker publish a proof after this downloader's
      # pre-lock observation. Keeping the exact expiry proves timestamps alone
      # cannot identify the proof that was checked.
      fresh.verification_expires_at = expiry
      fresh.verification_nonce = 'replacement-proof'
      source.revoked = true
    end
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      Service.new(record, source).download(access: nil, id: 1)
    end
    assert_equal 403, error.http_status
    assert_equal 'failed', record.state
    refute record.artifact.attached?
  end
end
