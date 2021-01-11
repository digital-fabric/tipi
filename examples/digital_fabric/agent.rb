# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'json'
require 'tipi/digital_fabric/protocol'

Protocol = Tipi::DigitalFabric::Protocol

def log(msg)
  puts "#{Time.now} #{msg}"
end

UPGRADE_REQUEST = <<~HTTP
  GET / HTTP/1.1
  Host: localhost
  Upgrade: df
  DF-Mount: path=/agent

HTTP

def df_upgrade(socket)
  log 'Upgrading connection'
  # cancel_after(10) do
    socket << UPGRADE_REQUEST
    while line = socket.gets
      break if line.chomp.empty?
    end
    log 'Connection upgraded'
  # end
end

def handle_df_msg(socket, msg)
  # log "recv #{msg.inspect}"
  case msg['kind']
  when Protocol::HTTP_REQUEST
    handle_http_request(socket, msg)
  when Protocol::WS_REQUEST
    handle_ws_request(socket, msg)
  when Protocol::PING
    log 'got ping from server'
  else
    log "Invalid DF message received: #{msg.inspect}"
  end
end

HTML_WS = IO.read(File.join(__dir__, 'ws_page.html'))
HTML_SSE = IO.read(File.join(__dir__, 'sse_page.html'))

def handle_http_request(socket, req)
  path = req['headers'][':path']
  case path
  when '/agent'
    send_df_message(socket, Protocol.http_response(
      req['id'],
      'Hello, world!',
      {},
      true
    ))
  when '/agent/ws'
    send_df_message(socket, Protocol.http_response(
      req['id'],
      HTML_WS,
      { 'Content-Type' => 'text/html' },
      true
    ))
  when '/agent/sse'
    send_df_message(socket, Protocol.http_response(
      req['id'],
      HTML_SSE,
      { 'Content-Type' => 'text/html' },
      true
    ))
  when '/agent/sse/events'
    spin { handle_sse_http_request(socket, req) }
  else
    send_df_message(socket, Protocol.http_response(
      req['id'],
      nil,
      { ':status' => 400 },
      true
    ))
  end

end

def handle_ws_request(socket, req)
  puts "handle_ws_request"
  send_df_message(socket, Protocol.ws_response(req['id'], {}))
  return spin { run_ws_connection(socket, req) }
end

def run_ws_connection(socket, req)
  10.times do
    sleep 1
    send_df_message(socket, Protocol.ws_data(req['id'], Time.now.to_s))
  end
  send_df_message(socket, Protocol.ws_close(req['id']))
end

def handle_sse_http_request(socket, req)
  send_df_message(socket, Protocol.http_response(
    req['id'],
    nil,
    { 'Content-Type' => 'text/event-stream' },
    false
  ))
  10.times do
    sleep 1
    send_df_message(socket, Protocol.http_response(
      req['id'],
      "data: #{Time.now}\n\n",
      nil,
      false
    ))
  end
  send_df_message(socket, Protocol.http_response(
    req['id'],
    "retry: 0\n\n",
    nil,
    true
  ))
end

def send_df_message(socket, msg)
  raise Polyphony::Cancel unless socket

  # log "send #{msg.inspect}"
  socket.puts msg.to_json
rescue Errno::EPIPE
  socket = nil
end

log 'Agent started'

socket = nil

spin_loop(interval: Protocol::SEND_TIMEOUT) do
  send_df_message(socket, Protocol.ping) if socket
end

loop do
  socket = Polyphony::Net.tcp_connect('127.0.0.1', 4411)
  log 'Connected to server'

  df_upgrade(socket)

  while (line = socket.gets)
    msg = JSON.parse(line) rescue nil
    handle_df_msg(socket, msg) if msg
  end
rescue SystemCallError, IOError, Polyphony::Cancel
  log 'Disconnected' if socket
  socket = nil
  sleep 1
end
