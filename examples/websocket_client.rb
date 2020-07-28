# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'websocket'

::Exception.__disable_sanitized_backtrace__ = true

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
    loop do
      data = @socket.readpartial(8192)
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


(1..3).each do |i|
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

suspend
