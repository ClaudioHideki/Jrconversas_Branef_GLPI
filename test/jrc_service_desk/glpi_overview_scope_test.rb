# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'active_support/all'

module JrcServiceDesk
  module Glpi; end
end

require_relative '../../app/services/jrc_service_desk/glpi/error'
require_relative '../../app/services/jrc_service_desk/glpi/overview'

class GlpiOverviewScopeTest < Minitest::Test
  Access = Struct.new(:connection) do
    def all_tickets? = false
    def glpi_user_id = 55
  end
  Query = Struct.new(:access) do
    def entity_ids = [7]
    def filters = {}
    def mine? = false
  end
  Run = Struct.new(:coverage) do
    def state = 'partial'
    def id = 1
    def finished_at = nil
  end

  # The ORM boundary has two collected rows and one visible actor row. SQL is
  # exercised by the real-DB integration regression; this fast check tests the
  # actual coverage renderer's handling of those two different counts.
  class Scope
    def initialize(count, actor_metadata: true)
      @count = count
      @actor_metadata = actor_metadata
    end

    def group(*) = self
    def count = { 7 => @count }

    def where(condition, *)
      return @actor_metadata ? [] : [true] if condition.include?('actor_scope_available')

      Scope.new(1)
    end
  end

  def test_restricted_coverage_uses_visible_actors_and_redacts_private_actor_errors
    access = Access.new(Struct.new(:lock_version).new(0))
    run = Run.new({ '7' => { 'state' => 'partial', 'observed' => 2, 'indexed' => 2, 'error' => 'OTHER_ACTOR_PRIVATE',
                            'actors' => [9999] } })
    coverage = JrcServiceDesk::Glpi::Overview.new.send(:coverage_for, access, Query.new(access), run, Scope.new(2))
    assert_equal 1, coverage.fetch(:observed)
    assert_equal 1, coverage.fetch(:indexed)
    assert_equal 'partial', coverage.fetch(:state)
    refute_includes coverage.to_json, 'OTHER_ACTOR_PRIVATE'
    refute_includes coverage.to_json, '9999'
  end

  def test_unavailable_actor_coverage_returns_no_counts
    access = Access.new(Struct.new(:lock_version).new(0))
    run = Run.new({ '7' => { 'state' => 'complete', 'observed' => 2, 'indexed' => 2 } })
    error = assert_raises(JrcServiceDesk::Glpi::Error) do
      JrcServiceDesk::Glpi::Overview.new.send(:coverage_for, access, Query.new(access), run, Scope.new(2, actor_metadata: false))
    end
    assert_equal 'projection_filter_unavailable', error.code
  end
end
