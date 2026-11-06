# frozen_string_literal: true

# Exercises the real session setup/cleanup, with a strictly local synthetic transport.
class IntakeReadinessProbe < JrcServiceDesk::Glpi::Client
  attr_reader :requests

  def initialize(connection, source)
    super(connection)
    @source = source
    @requests = []
  end

  def get(path, parameters = {})
    @requests << [:get, path]
    @source.get(path, parameters)
  end

  def collection(path, *args)
    @requests << [:get, path]
    @source.collection(path, *args)
  end

  private

  def request(method, path, **)
    @requests << [method, path]
    return { 'session_token' => 'synthetic-session' } if path == 'initSession/'
    return true if %w[changeActiveEntities/ killSession/].include?(path)

    raise 'Unexpected synthetic session request'
  end
end
