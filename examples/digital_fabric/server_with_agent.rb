# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'

opts = {
  reuse_addr:  true,
  dont_linger: true,
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

df_service = Tipi::DigitalFabric::Service.new
class MyAgentProxy < Tipi::DigitalFabric::AgentProxy
  def initialize
    @pending_requests = {}
    @last_request_id = 0
  end

  def http_request(req)
    req.respond('Hello world')
  end
end

agent = MyAgentProxy.new
df_service.mount({ catch_all: true }, agent)

Tipi.serve('0.0.0.0', 4411, opts) do |req|
  df_service.http_request(req)
end
