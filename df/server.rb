# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'
require 'tipi/digital_fabric/executive'
require 'json'
require 'fileutils'
FileUtils.cd(__dir__)

service = DigitalFabric::Service.new(token: 'foobar')
executive = DigitalFabric::Executive.new(service, { host: 'executive.realiteq.net' })

spin_loop(interval: 60) { GC.start }

class Polyphony::BaseException
  attr_reader :caller_backtrace
end

puts "pid: #{Process.pid}"

tcp_listener = spin do
  opts = {
    reuse_addr:  true,
    dont_linger: true,
  }
  puts 'Listening on localhost:4411'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 4411, opts)
  server.accept_loop do |client|
    spin do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    ensure
      service.decr_connection_count
    end
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
  Fiber.await(tcp_listener, unix_listener)
rescue Interrupt
  puts "Got SIGINT, shutting down gracefully"
  service.graceful_shutdown
  puts "post graceful shutdown"
end
