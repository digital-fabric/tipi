# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

spin do
  Tipi.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  rescue Exception => e
    p e
  end
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
suspend