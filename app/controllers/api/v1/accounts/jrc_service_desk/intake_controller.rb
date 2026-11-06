# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::IntakeController < Api::V1::Accounts::JrcServiceDesk::BaseController
  wrap_parameters false
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, with: :invalid_request

  def show
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    inbox = Current.account.inboxes.find(::JrcServiceDesk::Input.id(params.require(:inbox_id)))
    record = ::JrcServiceDesk::IntakeConfiguration.find_by(account_id: Current.account.id, inbox_id: inbox.id, current: true)
    render json: { record: record&.public_configuration }
  end

  def publish
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    record = ::JrcServiceDesk::Intake::Publish.new.call(user_context: pundit_user, attributes: request.request_parameters)
    render json: { record: record.public_configuration }, status: :created
  end

  def preview
    authorize ::JrcServiceDesk::IntakeConfiguration, :manage?
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[catalogue input])
    catalogue = ::JrcServiceDesk::Intake::Catalogue.new(values.fetch('catalogue'))
    input = ::JrcServiceDesk::Intake::Input.new(catalogue).call(values['input']) if values['input']
    selection = input&.except('identifier', 'identifier_type', 'email', 'description')
    render json: { valid: true, route_count: catalogue.route_count, selection: selection }
  end

  private

  def invalid_request
    render json: { error: 'INTAKE_CONFIGURATION_INVALID' }, status: :conflict
  end
end
