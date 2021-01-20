# frozen_string_literal: true

require 'digest/sha1'
require 'websocket'

module Tipi
  # Websocket connection
  class Websocket
    def self.handler(&block)
      proc { |conn, headers|
        block.(new(conn, headers))
      }
    end  

    def initialize(conn, headers)
      @conn = conn
      @headers = headers
      setup(headers)
    end
    
    S_WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    UPGRADE_RESPONSE = <<~HTTP.gsub("\n", "\r\n")
    HTTP/1.1 101 Switching Protocols
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Accept: %<accept>s
    
    HTTP
    
    def setup(headers)
      key = headers['sec-websocket-key']
      @version = headers['sec-websocket-version'].to_i
      accept = Digest::SHA1.base64digest([key, S_WS_GUID].join)
      @conn << format(UPGRADE_RESPONSE, accept: accept)
      
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
    
    def send(data)
      frame = ::WebSocket::Frame::Outgoing::Server.new(
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
