# frozen_string_literal: true

class JrcServiceDesk::Intake::ReadinessSource::ReadOnlySource
  def initialize(client)
    @client = client
    @cache = {}
  end

  def get(path) = @cache[[:get, path]] ||= @client.get(path).deep_dup
  def collection(path, *args) = @cache[[:collection, path, args]] ||= @client.collection(path, *args).deep_dup
end
