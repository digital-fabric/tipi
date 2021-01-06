# frozen_string_literal: true

require_relative './protocol'
require 'json'

module Tipi::DigitalFabric
  class Agent
    def initialize(df_service, req)
      @df_service = df_service
      @req = req
      @conn = req.adapter.conn
      @pending_requests = {}
      @last_request_id = 0
      run
    end

    def run
      @df_service.mount(route, self)
      while (line = @conn.gets)
        msg = JSON.parse(line)
        recv_df_message(msg)
      end
    ensure
      @df_service.unmount(self)
    end

    def route
      if (host = @req.headers['DF-Mount-Host'])
        { host: host }
      elsif (path = @req.headers['DF-Mount-Path'])
        { path: path }
      elsif (@req.headers['DF-Mount'] = 'catch-all')
        { catch_all: true }
      else
        nil
      end
    end

    def recv_df_message(message)
      kind = message['kind']
      method = :"recv_df_#{message['kind']}"
      send(method, message)
    end

    def send_df_message(message)
      @conn.puts(message.to_json)
    end

    def recv_df_http_response(message)
      handler = @pending_requests[message['id']]
      if !handler
        puts "Unknown HTTP request id in #{message}"
        return
      end

      handler << message
    end

    def recv_df_websocket(message)
      raise 'Not implemented'
    end

    def method_missing(sym, *args)
      # invalid DF message
      if sym =~ /^recv_df_/
        puts "Invalid DF message received #{sym.inspect} => #{args[0].inspect}"
        return
      end

      super
    end

    # HTTP / WebSocket

    def register_request_fiber
      id = (@last_request_id += 1)
      @pending_requests[id] = Fiber.current
      id
    end

    def unregister_request_fiber(id)
      @pending_requests.delete(id)
    end

    def with_request
      id = (@last_request_id += 1)
      @pending_requests[id] = Fiber.current
      yield id
    ensure
      @pending_requests.delete(id)
    end

    def http_request(req)
      with_request do |id|
        send_df_message(Protocol.http_request(id, req))
        # timeout = cancel_after(10)
        while (response = receive)
          # timeout.reset
          req.respond(response['body'], response['headers'] || {})
        # todo: implement streaming responses
          return
        end
      end
    rescue Polyphony::Cancel
      req.respond(nil, ':status' => 504)
    end

    def http_upgrade(req, protocol)
      case protocol
      when :websocket
        handle_websocket_upgrade(req)
      else
        handle_custom_upgrade(req, protocol)
      end
    end

    def handle_websocket_upgrade(req)
      ws = Tipi::Websocket.new(req.adapter.conn, req.headers)
      run_websocket_connection(ws)    
    end

    def run_websocket_connection(websocket)
      with_request do |id|
        send_df_message(df_websocket_start(id, req))
        reader = spin do
          websocket.recv_loop do |data|
          send_df_message(df_websocket_data(id, data))
        end
        while message = receive
          case message[:ws_msg_kind]
          when 'data'
            websocket << message[:data]
          when 'close'
            break
          end
        end
      ensure
        reader.terminate
      end
    end

    rescue Polyphony::Cancel
      send_df_message(df_websocket_close(id))
    end
  end
end
