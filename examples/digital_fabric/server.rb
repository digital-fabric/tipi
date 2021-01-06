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

Tipi.serve('0.0.0.0', 4411, opts) do |req|
  if req.headers[':path'] == '/foo'
    req.respond('bar')
    next
  end
  df_service.http_request(req)
end
