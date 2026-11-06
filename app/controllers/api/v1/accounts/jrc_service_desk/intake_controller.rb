# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::IntakeController < Api::V1::Accounts::JrcServiceDesk::BaseController
  wrap_parameters false
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, with: :invalid_request

  def show
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    inbox = Current.account.inboxes.find(::JrcServiceDesk::Input.id(params.require(:inbox_id)))
    record = ::JrcServiceDesk::IntakeConfiguration.find_by(account_id: Current.account.id, inbox_id: inbox.id, current: true)
    render json: envelope(record: record&.public_configuration)
  end

  def publish
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    record = ::JrcServiceDesk::Intake::Publish.new.call(user_context: pundit_user, attributes: request.request_parameters)
    render json: envelope(record: record.public_configuration), status: :created
  end

  def preview
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[catalogue input])
    catalogue = ::JrcServiceDesk::Intake::Catalogue.new(values.fetch('catalogue'))
    input = ::JrcServiceDesk::Intake::Input.new(catalogue).call(values['input']) if values['input']
    selection = input&.except('identifier', 'identifier_type', 'email', 'description')
    render json: { valid: true, route_count: catalogue.route_count, selection: selection }
  end

  def inboxes
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    rows = Current.account.inboxes.where(channel_type: 'Channel::Api').order(:name).map { |row| { id: row.id.to_s, name: row.name } }
    render json: envelope(inboxes: rows)
  end

  def readiness
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    result = ::JrcServiceDesk::Intake::Readiness.new.call(user_context: pundit_user, attributes: request.request_parameters)
    render json: envelope(result)
  end

  def conversation
    target = Current.account.conversations.find_by!(display_id: ::JrcServiceDesk::Input.id(params[:conversation_id]))
    authorize target, :show?
    rows = ::JrcServiceDesk::Intake::Visibility.new(pundit_user).call(target)
    render json: envelope(demands: rows)
  end

  def notice
    demand = authorized_demand
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[kind request_key human_confirmation])
    result = ::JrcServiceDesk::Intake::Notification.new.call(demand_id: demand.id, operator_context: pundit_user, **values.symbolize_keys)
    render json: envelope(notification: result.receipt)
  end

  def complete
    demand = authorized_demand
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[source_version])
    ::JrcServiceDesk::Intake::HumanCompletion.new.call(demand_id: demand.id, operator_context: pundit_user, source_version: values.fetch('source_version'))
    render json: envelope(completed: true)
  end

  private

  def authorized_demand
    demand = ::JrcServiceDesk::IntakeDemand.where(account_id: Current.account.id).find(::JrcServiceDesk::Input.id(params[:demand_id]))
    authorize demand.conversation, :show?
    raise Pundit::NotAuthorizedError unless ::JrcServiceDesk::Intake::Visibility.new(pundit_user).visible?(demand)

    demand
  end

  def envelope(values)
    values.merge(account_id: Current.account.id.to_s, user_id: Current.user.id.to_s)
  end

  def invalid_request
    render json: { error: 'INTAKE_CONFIGURATION_INVALID' }, status: :conflict
  end
end
