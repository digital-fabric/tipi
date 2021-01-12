# frozen_string_literal: true

require_relative './protocol'
require 'json'
require 'tipi/websocket'

module Tipi::DigitalFabric
  class Agent
    def initialize(host, port, route)
      @host = host
      @port = port
      @route = route
      @requests = {}
    end

    def run
      @keep_alive_timer = spin_loop(interval: 5) { keep_alive }
      while true
        connect && process_incoming_requests
      end
    ensure
      @keep_alive_timer.stop
    end

    def connect
      log 'Connecting...'
      @socket = Polyphony::Net.tcp_connect(@host, @port)
      log 'Connected to server'

      df_upgrade
      @last_recv = @last_send = Time.now
      true
    rescue IOError, Errno::ECONNREFUSED
      log 'Disconnected' if @socket
      sleep 5
      false
    end

    UPGRADE_REQUEST = <<~HTTP
    GET / HTTP/1.1
    Host: localhost
    Upgrade: df
    DF-Mount: %s
  
  HTTP
  
    def df_upgrade
      log 'Upgrading connection'
      @socket << format(UPGRADE_REQUEST, mount_point)
      while (line = @socket.gets)
        break if line.chomp.empty?
      end
      log 'Connection upgraded'
    end

    def mount_point
      if @route[:host]
        "host=#{@route[:host]}"
      elsif @route[:path]
        "path=#{@route[:path]}"
      else
        nil
      end
    end

    def log(msg)
      puts "#{Time.now} #{msg}"
    end

    def process_incoming_requests
      while (line = @socket.gets)
        msg = JSON.parse(line) rescue nil
        recv_df_message(msg) if msg
      end
    rescue IOError
      @socket = nil
      return
    end

    def keep_alive
      return unless @socket

      now = Time.now
      if now - @last_send >= Protocol::SEND_TIMEOUT
        send_df_message(Protocol.ping)
      end
      if now - @last_recv >= Protocol::RECV_TIMEOUT
        raise TimeoutError
      end
    end

    def recv_df_message(msg)
      @last_recv = Time.now
      case msg['kind']
      when Protocol::HTTP_REQUEST
        recv_http_request(msg)
      when Protocol::WS_REQUEST
        recv_ws_request(msg)
      when Protocol::CONN_DATA, Protocol::CONN_CLOSE,
           Protocol::WS_DATA, Protocol::WS_CLOSE
        fiber = @requests[msg['id']]
        fiber << msg if fiber
      end
    end

    def send_df_message(msg)
      @last_send = Time.now
      @socket.puts(msg.to_json)
    end

    def recv_http_request(req)
      spin do
        @requests[req['id']] = Fiber.current
        http_request(req)
      ensure
        @requests.delete(req['id'])
      end
    end

    def recv_ws_request(req)
      spin do
        @requests[req['id']] = Fiber.current
        ws_request(req)
      ensure
        @requests.delete(req['id'])
      end
    end

    def http_request(req)
      send_df_message(Protocol.http_response(
        req['id'], nil, { ':status': 501 }, true
      ))
    end

    def ws_request(req)
      send_df_message(Protocol.ws_response(
        req['id'], { ':status': 501 }
      ))
    end
  end
end
