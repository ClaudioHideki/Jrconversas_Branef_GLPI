# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'socket'
require 'uri'
require 'ssrf_filter'

# The application Client and all its parsers remain real. Only the production
# SSRF transport is replaced inside this standalone, disposable test process.
module GlpiLabTransport
  HOST = 'glpi.example.invalid'
  PORT = 14_443
  COUNTS = Hash.new(0)
  ITEM_MUTATIONS = Hash.new(0)
  SESSION_CONTROL_POSTS = Hash.new(0)

  def self.target!(value)
    uri = URI.parse(value)
    unless uri.is_a?(URI::HTTPS) && uri.host == HOST && uri.port == PORT && uri.userinfo.nil? &&
           uri.fragment.nil? && uri.path.start_with?('/apirest.php/')
      raise SecurityError, 'Refusing a non-laboratory GLPI target'
    end
    addresses = Addrinfo.getaddrinfo(uri.host, uri.port, nil, :STREAM).map(&:ip_address).uniq
    raise SecurityError, 'Laboratory hostname must resolve only to loopback' unless addresses == ['127.0.0.1']

    uri
  end

  def self.request(method, url, headers:, body: nil, max_redirects: 0, http_options: {}, **)
    raise SecurityError, 'Laboratory redirects are forbidden' unless max_redirects.zero?

    uri = target!(url)
    ca = File.expand_path('.runtime/tls/ca.crt', __dir__)
    http = Net::HTTP.new(uri.host, uri.port, nil) # Explicitly ignore every proxy environment variable.
    http.use_ssl = true
    http.ca_file = ca
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_hostname = true
    http.open_timeout = http_options.fetch(:open_timeout, 5)
    http.read_timeout = http_options.fetch(:read_timeout, 30)
    request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
    request = request_class.new(uri.request_uri, headers)
    request.body = body if body
    COUNTS[method] += 1
    if method == :post && uri.path == '/apirest.php/changeActiveEntities/'
      SESSION_CONTROL_POSTS[method] += 1
    elsif %i[post patch delete].include?(method)
      ITEM_MUTATIONS[method] += 1
    end
    http.start { |connection| connection.request(request) { |response| yield response } }
  end

  def self.install!
    unless ENV['GLPI_LAB_CONFIRM'] == 'isolated-synthetic' && ENV['RAILS_ENV'] == 'test' &&
           ENV['POSTGRES_DATABASE'] == 'branef_glpi_test'
      raise SecurityError, 'Refusing to install laboratory transport outside the disposable test environment'
    end
    adapter = Module.new
    %i[get post patch delete].each do |method|
      adapter.define_method(method) { |url, **options, &block| GlpiLabTransport.request(method, url, **options, &block) }
    end
    SsrfFilter.singleton_class.prepend(adapter)
  end
end
