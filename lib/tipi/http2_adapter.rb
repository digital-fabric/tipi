# frozen_string_literal: true

require 'http/2'
require_relative './http2_stream'

module Tipi
  # HTTP2 server adapter
  class HTTP2Adapter
    def self.upgrade_each(socket, opts, headers, &block)
      adapter = new(socket, opts, headers)
      adapter.each(&block)
    end
    
    def initialize(conn, opts, upgrade_headers = nil)
      @conn = conn
      @opts = opts
      @upgrade_headers = upgrade_headers
      @first = true
      
      @interface = ::HTTP2::Server.new
      @connection_fiber = Fiber.current
      @interface.on(:frame, &method(:send_frame))
      @streams = {}
    end
    
    def send_frame(data)
      @conn << data
    rescue Exception => e
      @connection_fiber.transfer e
    end
    
    UPGRADE_MESSAGE = <<~HTTP.gsub("\n", "\r\n")
    HTTP/1.1 101 Switching Protocols
    Connection: Upgrade
    Upgrade: h2c
    
    HTTP
    
    def upgrade
      @conn << UPGRADE_MESSAGE
      settings = @upgrade_headers['http2-settings']
      Fiber.current.schedule(nil)
      @interface.upgrade(settings, @upgrade_headers, '')
    ensure
      @upgrade_headers = nil
    end
    
    # Iterates over incoming requests
    def each(&block)
      @interface.on(:stream) { |stream| start_stream(stream, &block) }
      upgrade if @upgrade_headers
      
      @conn.recv_loop(&@interface.method(:<<))
    rescue SystemCallError, IOError
      # ignore
    ensure
      finalize_client_loop
    end
    
    def start_stream(stream, &block)
      stream = HTTP2StreamHandler.new(stream, @conn, @first, &block)
      @first = nil if @first
      @streams[stream] = true
    end
    
    def finalize_client_loop
      @interface = nil
      @streams.each_key(&:stop)
      @conn.close
    end
    
    def close
      @conn.close
    end
  end
end
