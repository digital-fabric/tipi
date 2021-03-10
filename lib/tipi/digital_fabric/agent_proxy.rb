# frozen_string_literal: true

require_relative './protocol'
require 'msgpack'
require 'tipi/websocket'

module DigitalFabric
  class AgentProxy
    def initialize(service, req)
      @service = service
      @req = req
      @conn = req.adapter.conn
      @msgpack_reader = MessagePack::Unpacker.new
      @requests = {}
      @current_request_count = 0
      @last_request_id = 0
      @last_recv = @last_send = Time.now
      run
    end

    def current_request_count
      @current_request_count
    end

    class TimeoutError < RuntimeError
    end

    class GracefulShutdown < RuntimeError
    end

    def run
      @fiber = Fiber.current
      @service.mount(route, self)
      keep_alive_timer = spin_loop(interval: 5) { keep_alive }
      process_incoming_messages(false)
    rescue GracefulShutdown
      puts "Proxy got graceful shutdown, left: #{@requests.size} requests" if @requests.size > 0
      process_incoming_messages(true)
    ensure
      keep_alive_timer&.stop
      @service.unmount(self)
    end

    def process_incoming_messages(shutdown = false)
      return if shutdown && @requests.empty?

      @conn.feed_loop(@msgpack_reader, :feed_each) do |msg|
        recv_df_message(msg)
        return if shutdown && @requests.empty?
      end
    rescue TimeoutError, IOError
    end

    def shutdown
      send_df_message(Protocol.shutdown)
      @fiber.raise GracefulShutdown.new
    end

    def keep_alive
      now = Time.now
      if now - @last_send >= Protocol::SEND_TIMEOUT
        send_df_message(Protocol.ping)
      end
      # if now - @last_recv >= Protocol::RECV_TIMEOUT
      #   raise TimeoutError
      # end
    rescue TimeoutError, IOError
    end

    def route
      case @req.headers['df-mount']
      when /^\s*host\s*=\s*([^\s]+)/
        { host: Regexp.last_match(1) }
      when /^\s*path\s*=\s*([^\s]+)/
        { path: Regexp.last_match(1) }
      when /catch_all/
        { catch_all: true }
      else
        nil
      end
    end

    def recv_df_message(message)
      @last_recv = Time.now
      return if message['kind'] == Protocol::PING

      handler = @requests[message['id']]
      if !handler
        # puts "Unknown request id in #{message}"
        return
      end

      handler << message
    end

    def send_df_message(message)
      @last_send = Time.now
      @conn << message.to_msgpack
    end

    # HTTP / WebSocket

    def register_request_fiber
      id = (@last_request_id += 1)
      @requests[id] = Fiber.current
      id
    end

    def unregister_request_fiber(id)
      @requests.delete(id)
    end

    def with_request
      @current_request_count += 1
      id = (@last_request_id += 1)
      @requests[id] = Fiber.current
      yield id
    ensure
      @current_request_count -= 1
      @requests.delete(id)
    end

    def http_request(req)
      t0 = Time.now
      t1 = nil
      with_request do |id|
        send_df_message(Protocol.http_request(id, req))
        while (message = receive)
          unless t1
            t1 = Time.now
            @service.record_latency_measurement(t1 - t0)
          end
          return if http_request_message(id, req, message)
        end
      end
    rescue => e
      req.respond("Error: #{e.inspect}\n#{e.backtrace.join("\n")}", ':status' => Qeweney::Status::INTERNAL_SERVER_ERROR)
    end

    # @return [Boolean] true if response is complete
    def http_request_message(id, req, message)
      case message['kind']
      when Protocol::HTTP_UPGRADE
        http_custom_upgrade(id, req, message)
        true
      when Protocol::HTTP_GET_REQUEST_BODY
        http_get_request_body(id, req, message)
        false
      when Protocol::HTTP_RESPONSE
        headers = message['headers']
        body = message['body']
        done = message['complete']
        transfer_count_key = message['transfer_count_key']
        if !req.headers_sent? && done
          req.respond(body, headers|| {})
          if transfer_count_key
            rx, tx = req.transfer_counts
            send_transfer_count(transfer_count_key, rx, tx)
          end
          true
        else
          req.send_headers(headers) if headers && !req.headers_sent?
          req.send_chunk(body, done: done) if body or done
          if done && transfer_count_key
            rx, tx = req.transfer_counts
            send_transfer_count(transfer_count_key, rx, tx)
          end
          done
        end
      else
        # invalid message
        true
      end
    end

    def send_transfer_count(key, rx, tx)
      send_df_message(Protocol.transfer_count(key, rx, tx))
    end

    HTTP_RESPONSE_UPGRADE_HEADERS = { ':status' => Qeweney::Status::SWITCHING_PROTOCOLS }

    def http_custom_upgrade(id, req, message)
      # send upgrade response
      upgrade_headers = message['headers'] ?
        message['headers'].merge(HTTP_RESPONSE_UPGRADE_HEADERS) :
        HTTP_RESPONSE_UPGRADE_HEADERS
      req.send_headers(upgrade_headers, true)

      conn = req.adapter.conn
      reader = spin do
        conn.recv_loop do |data|
          send_df_message(Protocol.conn_data(id, data))
        end
      end
      while (message = receive)
        return if http_custom_upgrade_message(conn, message)
      end
    ensure
      reader.stop
    end

    def http_custom_upgrade_message(conn, message)
      case message['kind']
      when Protocol::CONN_DATA
        conn << message['data']
        false
      when Protocol::CONN_CLOSE
        true
      else
        # invalid message
        true
      end
    end

    def http_get_request_body(id, req, message)
      case (limit = message['limit'])
      when nil
        body = req.read
      else
        limit = limit.to_i
        body = nil
        req.each_chunk do |chunk|
          (body ||= +'') << chunk
          break if body.bytesize >= limit
        end
      end
      send_df_message(Protocol.http_request_body(id, body, req.complete?))
    end

    def http_upgrade(req, protocol)
      if protocol == 'websocket'
        handle_websocket_upgrade(req)
      else
        # other protocol upgrades should be handled by the agent, so we just run
        # the request normally. The agent is expected to upgrade the connection
        # using a http_upgrade message. From that moment on, two-way
        # communication is handled using conn_data and conn_close messages.
        http_request(req)
      end
    end

    def handle_websocket_upgrade(req)
      with_request do |id|
        send_df_message(Protocol.ws_request(id, req.headers))
        response = receive
        case response['kind']
        when Protocol::WS_RESPONSE
          headers = response['headers'] || {} 
          status = headers[':status'] || Qeweney::Status::SWITCHING_PROTOCOLS
          if status != Qeweney::Status::SWITCHING_PROTOCOLS
            req.respond(nil, headers)
            return
          end
          ws = Tipi::Websocket.new(req.adapter.conn, req.headers)
          run_websocket_connection(id, ws)
        else
          req.respond(nil, ':status' => Qeweney::Status::SERVICE_UNAVAILABLE)
        end
      end
    end

    def run_websocket_connection(id, websocket)
      reader = spin do
        websocket.recv_loop do |data|
          send_df_message(Protocol.ws_data(id, data))
        end
      end
      while (message = receive)
        case message['kind']
        when Protocol::WS_DATA
          websocket << message['data']
        when Protocol::WS_CLOSE
          return
        else
          raise "Unexpected websocket message #{message.inspect}"
        end
      end
    ensure
      reader.stop
      websocket.close
    end
  end
end
