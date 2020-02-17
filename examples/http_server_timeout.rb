# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

def timeout_handler(timeout, &handler)
  ->(req) do
    cancel_after(timeout) { handler.(req) }
  rescue Polyphony::Cancel
    req.respond("timeout\n", ':status' => 502)
  end
end

sleep 0

spin do
  Polyphony::HTTP::Server.serve(
    '0.0.0.0',
    1234,
    opts,
    &timeout_handler(0.1) do |req|
      sleep rand(0.01..0.2)
      req.respond("Hello timeout world!\n")
    end
  )
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
suspend