# frozen_string_literal: true

class JrcServiceDesk::Glpi::Error < StandardError
  attr_reader :code, :http_status

  def initialize(code, http_status = 502)
    @code = code
    @http_status = http_status
    super(code)
  end
end
