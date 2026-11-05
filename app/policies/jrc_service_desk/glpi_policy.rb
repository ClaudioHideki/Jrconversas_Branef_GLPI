# frozen_string_literal: true

class JrcServiceDesk::GlpiPolicy < JrcServiceDesk::OperationalPolicy
  def read?
    operational_context.native_operator? && operational_context.capability?(:tickets_view)
  end

  def manage?
    read? && operational_context.administrator? && operational_context.capability?(:settings_view)
  end

  def create?
    read? && operational_context.capability?(:tickets_create)
  end

  def trash?
    read? && operational_context.administrator?
  end

  # Per-operation capabilities and live account/unit access are checked by Execute.
  def operate?
    read?
  end

  def report?
    read? && operational_context.capability?(:dashboard_view)
  end

  def export?
    report? && operational_context.capability?(:tickets_view_all)
  end
end
