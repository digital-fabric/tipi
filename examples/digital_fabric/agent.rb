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
  else
    log "Invalid DF message received: #{msg.inspect}"
  end
end

def handle_http_request(socket, req)
  if req['headers'][':path'] == '/sse' then
    return handle_sse_http_request(sockt, req)
  end

  send_df_message(socket, Protocol.http_response(
    req['id'],
    'Hello world',
    { 'DF-Foo' => 'bar' }
  ))
end

def handle_sse_http_request(socket, req)
  send_df_message(socket, Protocol.http_response(
    req['id'],
    nil,
    { 'Content_Type' => 'text/sse' },
    false
  ))
  throttled_loop(interval: 1) do
    messsage = Protocol.http_response(
      req['id'],
      "data: #{Time.now}\r\n",
      nil,
      false
    )
  end
end

def send_df_message(socket, msg)
  raise Polyphony::Cancel unless socket

  # log "send #{msg.inspect}"
  socket.puts msg.to_json
end

log 'Agent started'

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
