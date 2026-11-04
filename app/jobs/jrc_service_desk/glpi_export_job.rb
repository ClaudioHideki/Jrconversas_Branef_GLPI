# frozen_string_literal: true

class JrcServiceDesk::GlpiExportJob < ApplicationJob
  queue_as :low

  def perform(export_id, operation = 'generate')
    service = JrcServiceDesk::Glpi::Export.new
    case operation
    when 'generate' then service.generate(id: export_id)
    when 'verify' then service.verify(id: export_id)
    when 'expire' then service.expire(id: export_id)
    else raise ArgumentError
    end
  end
end
