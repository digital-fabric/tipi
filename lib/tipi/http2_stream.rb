# frozen_string_literal: true

require 'http/2'
require_relative './request'

module Tipi
  # Manages an HTTP 2 stream
  class HTTP2StreamHandler
    attr_accessor :__next__
    attr_reader :conn
    
    def initialize(stream, conn, first, &block)
      @stream = stream
      @conn = conn
      @first = first
      @connection_fiber = Fiber.current
      @stream_fiber = spin { |req| handle_request(req, &block) }
      
      # Stream callbacks occur on the connection fiber (see HTTP2Adapter#each).
      # The request handler is run on a separate fiber for each stream, allowing
      # concurrent handling of incoming requests on the same HTTP/2 connection.
      #
      # The different stream adapter APIs suspend the stream fiber, waiting for
      # stream callbacks to be called. The callbacks, in turn, transfer control to
      # the stream fiber, effectively causing the return of the adapter API calls.
      #
      # Note: the request handler is run once headers are received. Reading the
      # request body, if present, is at the discretion of the request handler.
      # This mirrors the behaviour of the HTTP/1 adapter.
      stream.on(:headers, &method(:on_headers))
      stream.on(:data, &method(:on_data))
      stream.on(:half_close, &method(:on_half_close))
    end
    
    def handle_request(request, &block)
      error = nil
      block.(request)
      @connection_fiber.schedule
    rescue Polyphony::MoveOn
      # ignore
    rescue Exception => e
      error = e
    ensure
      @done = true
      @connection_fiber.schedule error
    end
    
    def on_headers(headers)
      @request = Request.new(headers.to_h, self)
      if @first
        @request.headers[':first'] = true
        @first = false
      end
      @stream_fiber.schedule @request
    end
    
    def on_data(data)
      if @waiting_for_body_chunk
        @waiting_for_body_chunk = nil
        @stream_fiber.schedule data
      else
        @request.buffer_body_chunk(data)
      end
    end
    
    def on_half_close
      if @waiting_for_body_chunk
        @waiting_for_body_chunk = nil
        @stream_fiber.schedule
      elsif @waiting_for_half_close
        @waiting_for_half_close = nil
        @stream_fiber.schedule
      else
        @request.complete!
      end
    end
    
    def protocol
      'h2'
    end
    
    def get_body_chunk
      # called in the context of the stream fiber
      return nil if @request.complete?
      
      @waiting_for_body_chunk = true
      # the chunk (or an exception) will be returned once the stream fiber is
      # resumed
      suspend
    ensure
      @waiting_for_body_chunk = nil
    end
    
    # Wait for request to finish
    def consume_request
      return if @request.complete?
      
      @waiting_for_half_close = true
      suspend
    ensure
      @waiting_for_half_close = nil
    end
    
    # response API
    def respond(chunk, headers)
      headers[':status'] ||= '200'
      @stream.headers(headers, end_stream: false)
      @stream.data(chunk, end_stream: true)
      @headers_sent = true
    end
    
    def send_headers(headers, empty_response = false)
      return if @headers_sent
      
      headers[':status'] ||= (empty_response ? 204 : 200).to_s
      @stream.headers(headers, end_stream: false)
      @headers_sent = true
    end
    
    def send_chunk(chunk, done: false)
      send_headers({}, false) unless @headers_sent
      
      if chunk
        @stream.data(chunk, end_stream: done)
      elsif done
        @stream.close
      end
    end
    
    def finish
      if @headers_sent
        @stream.close
      else
        headers[':status'] ||= '204'
        @stream.headers(headers, end_stream: true)
      end
    end
    
    def stop
      return if @done
      
      @stream.close
      @stream_fiber.schedule(Polyphony::MoveOn.new)
    end
  end
end
