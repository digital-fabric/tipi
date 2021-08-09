# frozen_string_literal: true

require 'http/2'
require_relative './http2_stream'

# patch to fix bug in HTTP2::Stream
class HTTP2::Stream
  def end_stream?(frame)
    case frame[:type]
    when :data, :headers, :continuation
      frame[:flags]&.include?(:end_stream)
    else false
    end
  end
end

module Tipi
  # HTTP2 server adapter
  class HTTP2Adapter
    def self.upgrade_each(socket, opts, headers, body, &block)
      adapter = new(socket, opts, headers, body)
      adapter.each(&block)
    end
    
    def initialize(conn, opts, upgrade_headers = nil, upgrade_body = nil)
      @conn = conn
      @opts = opts
      @upgrade_headers = upgrade_headers
      @upgrade_body = upgrade_body
      @first = true
      @rx = (upgrade_headers && upgrade_headers[':rx']) || 0
      @tx = (upgrade_headers && upgrade_headers[':tx']) || 0

      @interface = ::HTTP2::Server.new
      @connection_fiber = Fiber.current
      @interface.on(:frame, &method(:send_frame))
      @streams = {}
    end
    
    def send_frame(data)
      if @transfer_count_request
        @transfer_count_request.tx_incr(data.bytesize)
      end
      @conn << data
    rescue Polyphony::BaseException
      raise
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
      @tx += UPGRADE_MESSAGE.bytesize
      settings = @upgrade_headers['http2-settings']
      @interface.upgrade(settings, @upgrade_headers, @upgrade_body || '')
    ensure
      @upgrade_headers = nil
    end
    
    # Iterates over incoming requests
    def each(&block)
      @interface.on(:stream) { |stream| start_stream(stream, &block) }
      upgrade if @upgrade_headers

      @conn.recv_loop do |data|
        @rx += data.bytesize
        @interface << data
      end
    rescue SystemCallError, IOError
      # ignore
    ensure
      finalize_client_loop
    end

    def get_rx_count
      count = @rx
      @rx = 0
      count
    end
    
    def get_tx_count
      count = @tx
      @tx = 0
      count
    end
    
    def start_stream(stream, &block)
      stream = HTTP2StreamHandler.new(self, stream, @conn, @first, &block)
      @first = nil if @first
      @streams[stream] = true
    end
    
    def finalize_client_loop
      @interface = nil
      @streams.each_key(&:stop)
      @conn.shutdown if @conn.respond_to?(:shutdown) rescue nil
      @conn.close
    end
    
    def close
      @conn.shutdown if @conn.respond_to?(:shutdown) rescue nil
      @conn.close
    end

    def set_request_for_transfer_count(request)
      @transfer_count_request = request
    end

    def unset_request_for_transfer_count(request)
      return unless @transfer_count_request == request

      @transfer_count_request = nil
    end
  end
end
