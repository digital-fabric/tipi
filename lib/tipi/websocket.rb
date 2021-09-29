# frozen_string_literal: true

require 'digest/sha1'
require 'websocket'

module Tipi
  # Websocket connection
  class Websocket
    def self.handler(&block)
      proc do |adapter, headers|
        req = Qeweney::Request.new(headers, adapter)
        websocket = req.upgrade_to_websocket
        block.(websocket)
      end
    end

    def initialize(conn, headers)
      @conn = conn
      @headers = headers
      @version = headers['sec-websocket-version'].to_i
      @reader = ::WebSocket::Frame::Incoming::Server.new(version: @version)
    end

    def recv
      if (msg = @reader.next)
        return msg.to_s
      end

      @conn.recv_loop do |data|
        @reader << data
        if (msg = @reader.next)
          return msg.to_s
        end
      end

      nil
    end

    def recv_loop
      if (msg = @reader.next)
        yield msg.to_s
      end

      @conn.recv_loop do |data|
        @reader << data
        while (msg = @reader.next)
          yield msg.to_s
        end
      end
    end

    OutgoingFrame = ::WebSocket::Frame::Outgoing::Server

    def send(data)
      frame = OutgoingFrame.new(
        version: @version, data: data, type: :text
      )
      @conn << frame.to_s
    end
    alias_method :<<, :send

    def close
      @conn.close
    end
  end
end
