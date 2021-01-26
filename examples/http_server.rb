# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

spin do
  Tipi.serve('0.0.0.0', 4411, opts) do |req|
    req.respond("Hello world!\n")
  rescue Exception => e
    p e
  end
  p 'done...'
end

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'
suspend