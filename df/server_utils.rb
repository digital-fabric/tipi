# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'
require 'tipi/digital_fabric/executive'
require 'json'
require 'fileutils'
require 'time'
require 'polyphony/extensions/debug'

FileUtils.cd(__dir__)

@service = DigitalFabric::Service.new(token: 'foobar')
@executive = DigitalFabric::Executive.new(@service, { host: '@executive.realiteq.net' })

@pid = Process.pid

def log(msg, **ctx)
  text = format(
    "%s (%d) %s\n",
    Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N'),
    @pid,
    msg
  )
  STDOUT.orig_write text
  return if ctx.empty?

  ctx.each { |k, v| STDOUT.orig_write format("  %s: %s\n", k, v.inspect) }
end

def listen_http
  spin(:http_listener) do
    opts = {
      reuse_addr:  true,
      dont_linger: true,
    }
    log('Listening for HTTP on localhost:10080')
    server = Polyphony::Net.tcp_listen('0.0.0.0', 10080, opts)
    id = 0
    loop do
      client = server.accept
      # log("Accept HTTP connection", client: client)
      spin("http#{id += 1}") do
        @service.incr_connection_count
        Tipi.client_loop(client, opts) { |req| @service.http_request(req) }
      ensure
        # log("Done with HTTP connection", client: client)
        @service.decr_connection_count
      end
    rescue Polyphony::BaseException
      raise
    rescue Exception => e
      log 'HTTP accept (unknown) error', error: e, backtrace: e.backtrace
    end
  end
end

CERTIFICATE_REGEXP = /(-----BEGIN CERTIFICATE-----\n[^-]+-----END CERTIFICATE-----\n)/.freeze

def listen_https
  spin(:https_listener) do
    private_key = OpenSSL::PKey::RSA.new IO.read('../../reality/ssl/privkey.pem')
    c = IO.read('../../reality/ssl/cacert.pem')
    certificates = c.scan(CERTIFICATE_REGEXP).map { |p|  OpenSSL::X509::Certificate.new(p.first) }
    ctx = OpenSSL::SSL::SSLContext.new
    cert = certificates.shift
    log "SSL Certificate expires: #{cert.not_after.inspect}"
    ctx.add_certificate(cert, private_key, certificates)
    ctx.ciphers = 'ECDH+aRSA'
    ctx.min_version = OpenSSL::SSL::TLS1_1_VERSION
    ctx.max_version = OpenSSL::SSL::TLS1_3_VERSION

    # TODO: further limit ciphers
    # ref: https://github.com/socketry/falcon/blob/3ec805b3ceda0a764a2c5eb68cde33897b6a35ff/lib/falcon/environments/tls.rb
    # ref: https://github.com/socketry/falcon/blob/3ec805b3ceda0a764a2c5eb68cde33897b6a35ff/lib/falcon/tls.rb

    opts = {
      reuse_addr:     true,
      dont_linger:    true,
      secure_context: ctx,
      alpn_protocols: Tipi::ALPN_PROTOCOLS
    }

    log('Listening for HTTPS on localhost:10443')
    server = Polyphony::Net.tcp_listen('0.0.0.0', 10443, opts)
    id = 0
    loop do
      client = server.accept
      # log('Accept HTTPS client connection', client: client)
      spin("https#{id += 1}") do
        @service.incr_connection_count
        Tipi.client_loop(client, opts) { |req| @service.http_request(req) }
      rescue => e
        log('Error while handling HTTPS client', client: client, error: e, backtrace: e.backtrace)
      ensure
        # log("Done with HTTP connection", client: client)
        @service.decr_connection_count
      end
    rescue OpenSSL::SSL::SSLError, SystemCallError, TypeError => e
      # log('HTTPS accept error', error: e, backtrace: e.backtrace)
    rescue Polyphony::BaseException
      raise
    rescue Exception => e
      log 'HTTPS accept (unknown) error', error: e, backtrace: e.backtrace
    end
  end
end

UNIX_SOCKET_PATH = '/tmp/df.sock'
def listen_unix
  spin(:unix_listener) do
    log("Listening on #{UNIX_SOCKET_PATH}")
    FileUtils.rm(UNIX_SOCKET_PATH) if File.exists?(UNIX_SOCKET_PATH)
    socket = UNIXServer.new(UNIX_SOCKET_PATH)

    id = 0
    loop do
      client = socket.accept
      # log('Accept Unix connection', client: client)
      spin("unix#{id += 1}") do
        Tipi.client_loop(client, {}) { |req| @service.http_request(req, true) }
      end
    rescue Polyphony::BaseException
      raise
    rescue Exception => e
      log 'Unix accept error', error: e, backtrace: e.backtrace
    end
  end
end

def listen_df
  spin(:df_listener) do
    opts = {
      reuse_addr:  true,
      reuse_port:  true,
      dont_linger: true,
    }
    log('Listening for DF connections on localhost:4321')
    server = Polyphony::Net.tcp_listen('0.0.0.0', 4321, opts)

    id = 0
    loop do
      client = server.accept
      # log('Accept DF connection', client: client)
      spin("df#{id += 1}") do
        Tipi.client_loop(client, {}) { |req| @service.http_request(req, true) }
      end
    rescue Polyphony::BaseException
      raise
    rescue Exception => e
      log 'DF accept (unknown) error', error: e, backtrace: e.backtrace
    end
  end
end

if ENV['TRACE'] == '1'
  Thread.backend.trace_proc = proc do |event, fiber, value, pri|
    fiber_id = fiber.tag || fiber.inspect
    case event
    when :fiber_schedule
      log format("=> %s %s %s %s", event, fiber_id, value.inspect, pri ? '(priority)' : '')
    when :fiber_run
      log format("=> %s %s %s", event, fiber_id, value.inspect)
    when :fiber_create, :fiber_terminate
      log format("=> %s %s", event, fiber_id)
    else
      log format("=> %s", event)
    end
  end
end
