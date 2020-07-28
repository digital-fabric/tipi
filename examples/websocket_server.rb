# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/websocket'

def ws_handler(conn)
  while (msg = conn.recv)
    conn << "you said: #{msg}"
  end
end

opts = {
  reuse_addr:  true,
  dont_linger: true,
  upgrade:     {
    websocket: Tipi::Websocket.handler(&method(:ws_handler))
  }
}

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
Tipi.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end
