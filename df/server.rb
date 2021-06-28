# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'
require 'tipi/digital_fabric/executive'
require 'json'
require 'fileutils'
require 'localhost/authority'

FileUtils.cd(__dir__)

service = DigitalFabric::Service.new(token: 'foobar')
executive = DigitalFabric::Executive.new(service, { host: 'executive.realiteq.net' })

GC.disable
Thread.current.backend.idle_gc_period = 60

# spin_loop(interval: 60) { GC.start }
require 'time'

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

class Polyphony::BaseException
  attr_reader :caller_backtrace
end

http_listener = spin(:http_listener) do
  opts = {
    reuse_addr:  true,
    dont_linger: true,
  }
  log('Listening for HTTP on localhost:10080')
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10080, opts)
  id = 0
  loop do
    client = server.accept
    log("Accept HTTP connection", client: client)
    spin("http#{id += 1}") do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    ensure
      log("Done with HTTP connection", client: client)
      service.decr_connection_count
    end
  rescue => e
    log("HTTP accept loop error", error: e, backtrace: e.backtrace)
  end
end

CERTIFICATE_REGEXP = /(-----BEGIN CERTIFICATE-----\n[^-]+-----END CERTIFICATE-----\n)/.freeze

https_listener = spin('https_listener') do
  private_key = OpenSSL::PKey::RSA.new IO.read('../../reality/ssl/privkey.pem')
  c = IO.read('../../reality/ssl/cacert.pem')
  certificates = c.scan(CERTIFICATE_REGEXP).map { |p|  OpenSSL::X509::Certificate.new(p.first) }
  ctx = OpenSSL::SSL::SSLContext.new
  cert = certificates.shift
  puts "Certificate expires: #{cert.not_after.inspect}"
  ctx.add_certificate(cert, private_key, certificates)
  ctx.ciphers = 'ECDH+aRSA'

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
    log('Accept HTTPS client connection', client: client)
    spin("https#{id += 1}") do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    rescue => e
      log('Error while handling HTTPS client', client: client, error: e, backtrace: e.backtrace)
    ensure
      log("Done with HTTP connection", client: client)
      service.decr_connection_count
    end
  rescue OpenSSL::SSL::SSLError, SystemCallError, TypeError => e
    log('HTTPS accept error', error: e, backtrace: e.backtrace)
  rescue => e
    log('HTTPS accept (unknown) error', error: e, backtrace: e.backtrace)
  end
end

UNIX_SOCKET_PATH = '/tmp/df.sock'
unix_listener = spin('unix_listener') do
  log("Listening on #{UNIX_SOCKET_PATH}")
  FileUtils.rm(UNIX_SOCKET_PATH) if File.exists?(UNIX_SOCKET_PATH)
  socket = UNIXServer.new(UNIX_SOCKET_PATH)

  id = 0
  socket.accept_loop do |client|
    log('Accept Unix connection', client: client)
    spin("unix#{id += 1}") do
      Tipi.client_loop(client, {}) { |req| service.http_request(req) }
    end
  rescue OpenSSL::SSL::SSLError
    # disregard
  end
end

Thread.backend.trace_proc = proc do |event, fiber, value|
  fiber_id = fiber.tag || fiber.inspect
  case event
  when :fiber_schedule, :fiber_run
    log format("=> %s %s %s", event, fiber_id, value.inspect)
  when :fiber_create, :fiber_terminate
    log format("=> %s %s", event, fiber_id)
  else
    log format("=> %s", event)
  end
end

begin
  log('Starting DF server')
  Fiber.await(http_listener, https_listener, unix_listener)
rescue Interrupt
  log('Got SIGINT, shutting down gracefully')
  service.graceful_shutdown
rescue Exception => e
  log("Uncaught exception", error: e, backtrace: e.backtrace)
ensure
  log('DF server stopped')
end
