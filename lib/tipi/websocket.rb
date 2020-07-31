# frozen_string_literal: true

require 'digest/sha1'
require 'websocket'

module Tipi
  # Websocket connection
  class Websocket
    def self.handler(&block)
      proc { |client, header|
        block.(new(client, header))
      }
    end  

    def initialize(client, headers)
      @client = client
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
      key = headers['Sec-WebSocket-Key']
      @version = headers['Sec-WebSocket-Version'].to_i
      accept = Digest::SHA1.base64digest([key, S_WS_GUID].join)
      @client << format(UPGRADE_RESPONSE, accept: accept)
      
      @reader = ::WebSocket::Frame::Incoming::Server.new(version: @version)
    end
    
    def recv
      if (msg = @reader.next)
        return msg.to_s
      end
    
      @client.read_loop do |data|
        @reader << data
        if (msg = @reader.next)
          break msg.to_s
        end
      end
      
      nil
    end
    
    def send(data)
      frame = ::WebSocket::Frame::Outgoing::Server.new(
        version: @version, data: data, type: :text
      )
      @client << frame.to_s
    end
    alias_method :<<, :send
  end
end
