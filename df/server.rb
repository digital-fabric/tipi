# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'
require 'tipi/digital_fabric/executive'
require 'json'
require 'fileutils'
FileUtils.cd(__dir__)

service = DigitalFabric::Service.new(token: 'foobar')
# executive = DigitalFabric::Executive.new(service, { host: 'executive.realiteq.net' })

# spin_loop(interval: 60) { GC.start }
# spin_loop(interval: 10) { puts "#{Time.now} #{executive.last_service_stats}" }

trap("SIGINT") { raise Interrupt }

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
  Tipi.serve('0.0.0.0', 4411, opts) do |req|
    service.http_request(req)
  end
# rescue Polyphony::Terminate => e
#   puts 'Got Polyphony::Terminate'
#   p({
#     raising_fiber: e.raising_fiber,
#     caller_backtrace: e.caller_backtrace
#   })
#   exit!
end

UNIX_SOCKET_PATH = '/tmp/df.sock'

unix_listener = spin do
  puts "Listening on #{UNIX_SOCKET_PATH}"
  FileUtils.rm(UNIX_SOCKET_PATH) if File.exists?(UNIX_SOCKET_PATH)
  socket = UNIXServer.new(UNIX_SOCKET_PATH)
  Tipi.accept_loop(socket, {}) do |req|
    service.http_request(req)
  end
end

begin
  Fiber.await(tcp_listener, unix_listener)
rescue Interrupt
  puts "Got SIGINT, shutting down gracefully"
  service.graceful_shutdown
  puts "post graceful shutdown"
end
