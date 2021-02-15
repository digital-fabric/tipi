# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/websocket'

def ws_handler(conn)
  timer = spin_loop(interval: 1) do
    conn << Time.now.to_s
  end
  while (msg = conn.recv)
    conn << "you said: #{msg}"
  end
ensure
  timer.stop
end

opts = {
  reuse_addr:  true,
  dont_linger: true,
}

HTML = IO.read(File.join(__dir__, 'ws_page.html'))

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

Tipi.serve('0.0.0.0', 4411, opts) do |req|
  if req.upgrade_protocol == 'websocket'
    conn = req.upgrade_to_websocket
    ws_handler(conn)
  else
    req.respond(HTML, 'Content-Type' => 'text/html')
  end
end
