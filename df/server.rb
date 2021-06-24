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

class Polyphony::BaseException
  attr_reader :caller_backtrace
end

puts "pid: #{Process.pid}"

http_listener = spin do
  opts = {
    reuse_addr:  true,
    dont_linger: true,
  }
  puts 'Listening for HTTP on localhost:10080'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10080, opts)
  server.accept_loop do |client|
    spin do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    ensure
      service.decr_connection_count
    end
  rescue Exception => e
    puts "HTTP accept_loop error: #{e.inspect}"
    puts e.backtrace.join("\n")
  end
end

CERTIFICATE_REGEXP = /(-----BEGIN CERTIFICATE-----\n[^-]+-----END CERTIFICATE-----\n)/.freeze

https_listener = spin do
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

  puts 'Listening for HTTPS on localhost:10443'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10443, opts)
  loop do
    client = server.accept
    spin do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    rescue Exception => e
      puts "Exception: #{e.inspect}"
      puts e.backtrace.join("\n")
    ensure
      service.decr_connection_count
    end
  rescue Polyphony::BaseException
    raise
  rescue OpenSSL::SSL::SSLError, SystemCallError => e
    puts "HTTPS accept error: #{e.inspect}"
  rescue Exception => e
    puts "HTTPS accept error: #{e.inspect}"
    puts e.backtrace.join("\n")
  end
end

UNIX_SOCKET_PATH = '/tmp/df.sock'
unix_listener = spin do
  puts "Listening on #{UNIX_SOCKET_PATH}"
  FileUtils.rm(UNIX_SOCKET_PATH) if File.exists?(UNIX_SOCKET_PATH)
  socket = UNIXServer.new(UNIX_SOCKET_PATH)
  Tipi.accept_loop(socket, {}) { |req| service.http_request(req) }
end

begin
  Fiber.await(http_listener, https_listener, unix_listener)
rescue Interrupt
  puts "Got SIGINT, shutting down gracefully"
  service.graceful_shutdown
  puts "post graceful shutdown"
rescue Exception => e
  puts '*' * 40
  p e
  puts e.backtrace.join("\n")
end
