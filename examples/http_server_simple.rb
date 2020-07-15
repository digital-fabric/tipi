# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'

Tipi.serve('0.0.0.0', 1234) do |req|
  req.respond("Hello world!\n")
end
