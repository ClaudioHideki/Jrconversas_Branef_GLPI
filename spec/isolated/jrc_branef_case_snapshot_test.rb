# frozen_string_literal: true

require 'minitest/autorun'

# Load the real controller with ports for Rails, authorization and the GLPI reader.
module Api; module V1; module Accounts; module JrcServiceDesk
  class OperationsController
    def self.skip_around_action(*) = nil
    def self.rescue_from(*) = nil
  end
end; end; end; end
module JrcProjects; module Errors; class WipLimit < StandardError; end; end; end
module JrcApprovals; class Error < StandardError; end; end
module JrcServiceDesk
  class AttachmentScanError < StandardError; end
  module Glpi
    class LinkedReferences
      def call(**values)
        { id: values.fetch(:incident_id), transaction_open: ActiveRecord::Base.connection.transaction_open? }
      end
    end
  end
end
module ActiveRecord
  class Base
    class << self
      attr_accessor :open, :transactions
      def connection = self
      def transaction_open? = !!open
      def transaction(isolation:)
        raise 'unexpected snapshot isolation' unless isolation == :repeatable_read
        raise 'nested isolation change' if transaction_open?
        self.transactions += 1
        self.open = true
        yield
      ensure
        self.open = false
      end
    end
  end
end
require_relative '../../app/controllers/api/v1/accounts/jrc_service_desk/case_workspaces_controller'

class BranefCaseSnapshotTest < Minitest::Test
  class Controller < Api::V1::Accounts::JrcServiceDesk::CaseWorkspacesController
    attr_reader :output
    def query_values = {}
    def scoped_case = Struct.new(:id).new(77)
    def authorize(*) = nil
    def case_presenter = ->(row) { { id: row.id, native_snapshot: ActiveRecord::Base.connection.transaction_open? } }
    def pundit_user = :authorized_context
    def base_payload = { contract_version: 1 }
    def render(json:) = @output = json
  end

  def setup
    ActiveRecord::Base.open = false
    ActiveRecord::Base.transactions = 0
  end

  def test_native_snapshot_is_closed_before_the_remote_glpi_read
    controller = Controller.new
    controller.show
    assert_equal 1, ActiveRecord::Base.transactions
    assert controller.output.dig(:record, :native_snapshot)
    refute controller.output.dig(:record, :glpi_references, :transaction_open)
    assert_equal 77, controller.output.dig(:record, :glpi_references, :id)
  end

  def test_existing_snapshot_is_reused_without_a_nested_isolation_change
    ActiveRecord::Base.open = true
    controller = Controller.new
    controller.show
    assert_equal 0, ActiveRecord::Base.transactions
    assert controller.output.dig(:record, :native_snapshot)
    assert ActiveRecord::Base.open
  end
end
