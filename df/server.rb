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

spin_loop(interval: 60) { GC.start }

class Polyphony::BaseException
  attr_reader :caller_backtrace
end

class OpenSSL::SSL::SSLServer
  def accept_loop
    loop do
      yield accept
    rescue SystemCallError, OpenSSL::SSL::SSLError, RuntimeError => e
      puts "Accept error: #{e.inspect}"
    end
  end
end

class OpenSSL::SSL::SSLSocket
  alias_method :recv_loop, :read_loop

  alias_method :orig_peeraddr, :peeraddr
  def peeraddr(_ = nil)
    orig_peeraddr
  end
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

https_listener = spin do
  c = IO.read('../../reality/ssl/cacert.pem')
  certificates = c.split("\n-----END CERTIFICATE-----\n").map { |c| OpenSSL::X509::Certificate.new(c + "\n-----END CERTIFICATE-----\n") }
  private_key = OpenSSL::PKey::RSA.new IO.read('../../reality/ssl/privkey.pem')
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.add_certificate(certificates.shift, private_key, certificates)
  # ctx = Localhost::Authority.fetch.server_context
  opts = {
    reuse_addr:     true,
    dont_linger:    true,
    secure_context: ctx,
    alpn_protocols: Tipi::ALPN_PROTOCOLS
  }

  puts 'Listening for HTTPS on localhost:10443'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10443, opts)
  server.accept_loop do |client|
    spin do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    ensure
      service.decr_connection_count
    end
  rescue Exception => e
    puts "HTTPS accept_loop error: #{e.inspect}"
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
