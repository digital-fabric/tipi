# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'
require 'tipi/digital_fabric/executive'
require 'json'

opts = {
  reuse_addr:  true,
  dont_linger: true,
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

class DevAgent
  def http_request(req)
    response = {
      result: 'OK',
      time: Time.now.to_f,
      machine: 'dev',
      process: 'DF1'
    }
    req.respond(response.to_json, { 'Content-Type' => 'text/json' })
  end
end

service = DigitalFabric::Service.new(token: 'foobar')
DigitalFabric::Executive.new(service, { host: 'executive.realiteq.net' })
service.mount({ host: 'dev.realiteq.net' }, DevAgent.new)
service.mount({ host: '172.31.41.85:4411' }, DevAgent.new) # for ELB health checks

spin_loop(interval: 60) { GC.start }

begin
  Tipi.serve('0.0.0.0', 4411, opts) do |req|
    if req.headers[':path'] == '/foo'
      req.respond('bar')
      next
    end
    service.http_request(req)
  end
rescue Interrupt
  puts "Got SIGINT, shutting down gracefully"
  service.graceful_shutdown
end
