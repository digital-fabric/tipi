# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

spin do
  Tipi.serve('0.0.0.0', 4411, opts) do |req|
    body = req.read
    body2 = req.read
    req.respond("body: #{body} (body2: #{body2.inspect})\n")
  rescue Exception => e
    p e
  end
  p 'done...'
end.await
