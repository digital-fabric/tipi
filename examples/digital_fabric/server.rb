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

df_service = Tipi::DigitalFabric::Service.new
Tipi::DigitalFabric::Executive.new(df_service, { host: 'executive.realiteq.net' })
df_service.mount({ host: 'dev.realiteq.net' }, DevAgent.new)
df_service.mount({ host: '172.31.41.85:4411' }, DevAgent.new) # for ELB health checks


Tipi.serve('0.0.0.0', 4411, opts) do |req|
  if req.headers[':path'] == '/foo'
    req.respond('bar')
    next
  end
  df_service.http_request(req)
end
