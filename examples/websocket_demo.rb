# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/websocket'

class WebsocketClient
  def initialize(url, headers = {})
    @socket = TCPSocket.new('127.0.0.1', 1234)
    do_handshake(url, headers)
  end

  def do_handshake(url, headers)
    handshake = WebSocket::Handshake::Client.new(url: url, headers: headers)
    @socket << handshake.to_s
    @socket.read_loop do |data|
      handshake << data
      break if handshake.finished?
    end
    raise 'Websocket handshake failed' unless handshake.valid?
    @version = handshake.version

    @reader = WebSocket::Frame::Incoming::Client.new(version: @version)
  end

  def receive
    parsed = @reader.next
    return parsed if parsed

    @socket.read_loop do |data|
      @reader << data
      parsed = @reader.next
      return parsed if parsed
    end
  end

  def send(data)
    frame = WebSocket::Frame::Outgoing::Client.new(
      version: @version,
      data: data,
      type: :text
    )
    @socket << frame.to_s
  end
  alias_method :<<, :send

  def close
    @socket.close
  end
end

server = spin do
  websocket_handler = Tipi::Websocket.handler do |conn|
    while (msg = conn.recv)
      conn << "you said: #{msg}"
    end
  end

  opts = { upgrade: { websocket: websocket_handler } }
  puts 'Listening on port http://127.0.0.1:1234/'
  Tipi.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
end

sleep 0.01 # wait for server to start

clients = (1..3).map do |i|
  spin do
    client = WebsocketClient.new('ws://127.0.0.1:1234/', { Cookie: "SESSIONID=#{i * 10}" })
    (1..3).each do |j|
      sleep rand(0.2..0.5)
      client.send "Hello from client #{i} (#{j})"
      puts "server reply: #{client.receive}"
    end
    client.close
  end
end

Fiber.await(*clients)
