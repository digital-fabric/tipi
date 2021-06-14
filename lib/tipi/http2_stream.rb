# frozen_string_literal: true

require 'http/2'
require 'qeweney/request'

module Tipi
  # Manages an HTTP 2 stream
  class HTTP2StreamHandler
    attr_accessor :__next__
    attr_reader :conn
    
    def initialize(adapter, stream, conn, first, &block)
      @adapter = adapter
      @stream = stream
      @conn = conn
      @first = first
      @connection_fiber = Fiber.current
      @stream_fiber = spin { |req| handle_request(req, &block) }
      Thread.current.fiber_unschedule(@stream_fiber)

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
      @request = Qeweney::Request.new(headers.to_h, self)
      @request.rx_incr(@adapter.get_rx_count)
      @request.tx_incr(@adapter.get_tx_count)
      if @first
        @request.headers[':first'] = true
        @first = false
      end
      @stream_fiber.schedule @request
    end

    def on_data(data)
      data = data.to_s # chunks might be wrapped in a HTTP2::Buffer
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

    def with_transfer_count(request)
      @adapter.set_request_for_transfer_count(request)
      yield
    ensure
      @adapter.unset_request_for_transfer_count(request)
    end
    
    def get_body_chunk(request)
      # called in the context of the stream fiber
      return nil if @request.complete?
      
      with_transfer_count(request) do
        @waiting_for_body_chunk = true
        # the chunk (or an exception) will be returned once the stream fiber is
        # resumed 
        suspend
      end
    ensure
      @waiting_for_body_chunk = nil
    end
    
    # Wait for request to finish
    def consume_request(request)
      return if @request.complete?
      
      with_transfer_count(request) do
        @waiting_for_half_close = true
        suspend
      end
    ensure
      @waiting_for_half_close = nil
    end
    
    # response API
    def respond(request, chunk, headers)
      headers[':status'] ||= Qeweney::Status::OK
      headers[':status'] = headers[':status'].to_s
      with_transfer_count(request) do
        @stream.headers(transform_headers(headers))
        @stream.data(chunk || '')
      end
      @headers_sent = true
    rescue HTTP2::Error::StreamClosed
      # ignore
    end

    def transform_headers(headers)
      headers.each_with_object([]) do |(k, v), a|
        if v.is_a?(Array)
          v.each { |vv| a << [k, vv.to_s] }
        else
          a << [k, v.to_s]
        end
      end
    end
    
    def send_headers(request, headers, empty_response = false)
      return if @headers_sent
      
      headers[':status'] ||= (empty_response ? Qeweney::Status::NO_CONTENT : Qeweney::Status::OK).to_s
      with_transfer_count(request) do
        @stream.headers(transform_headers(headers), end_stream: false)
      end
      @headers_sent = true
    rescue HTTP2::Error::StreamClosed
      # ignore
    end
    
    def send_chunk(request, chunk, done: false)
      send_headers({}, false) unless @headers_sent
      
      if chunk
        with_transfer_count(request) do
          @stream.data(chunk, end_stream: done)
        end
      elsif done
        @stream.close
      end
    rescue HTTP2::Error::StreamClosed
      # ignore
    end
    
    def finish(request)
      if @headers_sent
        @stream.close
      else
        headers[':status'] ||= Qeweney::Status::NO_CONTENT
        with_transfer_count(request) do
          @stream.headers(transform_headers(headers), end_stream: true)
        end
      end
    rescue HTTP2::Error::StreamClosed
      # ignore
    end
    
    def stop
      return if @done
      
      @stream.close
      @stream_fiber.schedule(Polyphony::MoveOn.new)
    end
  end
end
