# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'localhost/authority'

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
app = Polyphony::HTTP::Server::RackAdapter.load(app_path)

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: authority.server_context
}

puts 'listening on port 1234'
puts "pid: #{Process.pid}"
Tipi.serve('0.0.0.0', 1234, opts, &app)
