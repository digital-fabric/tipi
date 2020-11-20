# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

::Exception.__disable_sanitized_backtrace__ = true

opts = {
  reuse_addr:     true,
  reuse_port:     true,
  dont_linger:    true
}

server = Tipi.listen('0.0.0.0', 1234, opts)

puts 'Listening on port 1234'

throttler = Polyphony::Throttler.new(interval: 5)
server.accept_loop do |socket|
  throttler.call do
    spin { Tipi.client_loop(socket, opts) { |req| req.respond("Hello world!\n") } }
  end
end
