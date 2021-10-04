# frozen_string_literal: true

require 'h1p'
require 'qeweney/request'

require_relative './http2_adapter'

module Tipi
  # HTTP1 protocol implementation
  class HTTP1Adapter
    attr_reader :conn

    # Initializes a protocol adapter instance
    def initialize(conn, opts)
      @conn = conn
      @opts = opts
      @first = true
      @parser = H1P::Parser.new(@conn)
    end
    
    def each(&block)
      while true
        headers = @parser.parse_headers
        break unless headers
        
        # handle_request returns true if connection is not persistent or was
        # upgraded
        break if handle_request(headers, &block)
      end
    rescue H1P::Error, ArgumentError
      # an ArgumentError might be raised in the parser if an invalid input
      # string is given as the HTTP method (String#upcase will raise on invalid HTTP string)
      #
      # ignore
    rescue SystemCallError, IOError
      # ignore
    ensure
      finalize_client_loop
    end
    
    def handle_request(headers, &block)
      scheme = (proto = headers['x-forwarded-proto']) ?
                proto.downcase : scheme_from_connection
      headers[':scheme'] = scheme
      @protocol = headers[':protocol']
      if @first
        headers[':first'] = true
        @first = nil
      end
      
      return true if upgrade_connection(headers, &block)
      
      request = Qeweney::Request.new(headers, self)
      if !@parser.complete?
        request.buffer_body_chunk(@parser.read_body_chunk(true))
      end
      block.call(request)
      return !persistent_connection?(headers)
    end

    def persistent_connection?(headers)
      if headers[':protocol'] == 'http/1.1'
        return headers['connection'] != 'close'
      else
        connection = headers['connection']
        return connection && connection != 'close'
      end
    end
    
    def finalize_client_loop
      @parser = nil
      @splicing_pipe = nil
      @conn.shutdown if @conn.respond_to?(:shutdown) rescue nil
      @conn.close
    end
    
    # Reads a body chunk for the current request. Transfers control to the parse
    # loop, and resumes once the parse_loop has fired the on_body callback
    def get_body_chunk(request, buffered_only = false)
      @parser.read_body_chunk(buffered_only)
    end

    def get_body(request)
      @parser.read_body
    end

    def complete?(request)
      @parser.complete?
    end
    
    def protocol
      @protocol
    end
    
    # Upgrades the connection to a different protocol, if the 'Upgrade' header is
    # given. By default the only supported upgrade protocol is HTTP2. Additional
    # protocols, notably WebSocket, can be specified by passing a hash to the
    # :upgrade option when starting a server:
    #
    #     def ws_handler(conn)
    #       conn << 'hi'
    #       msg = conn.recv
    #       conn << "You said #{msg}"
    #       conn << 'bye'
    #       conn.close
    #     end
    #
    #     opts = {
    #       upgrade: {
    #         websocket: Tipi::Websocket.handler(&method(:ws_handler))
    #       }
    #     }
    #     Tipi.serve('0.0.0.0', 1234, opts) { |req| ... }
    #
    # @param headers [Hash] request headers
    # @return [boolean] truthy if the connection has been upgraded
    def upgrade_connection(headers, &block)
      upgrade_protocol = headers['upgrade']
      return nil unless upgrade_protocol
      
      upgrade_protocol = upgrade_protocol.downcase.to_sym
      upgrade_handler = @opts[:upgrade] && @opts[:upgrade][upgrade_protocol]
      return upgrade_with_handler(upgrade_handler, headers) if upgrade_handler
      return upgrade_to_http2(headers, &block) if upgrade_protocol == :h2c
      
      nil
    end
    
    def upgrade_with_handler(handler, headers)
      @parser = nil
      handler.(self, headers)
      true
    end
    
    def upgrade_to_http2(headers, &block)
      headers = http2_upgraded_headers(headers)
      body = @parser.read_body
      HTTP2Adapter.upgrade_each(@conn, @opts, headers, body, &block)
      true
    end
    
    # Returns headers for HTTP2 upgrade
    # @param headers [Hash] request headers
    # @return [Hash] headers for HTTP2 upgrade
    def http2_upgraded_headers(headers)
      headers.merge(
        ':scheme'    => 'http',
        ':authority' => headers['host']
      )
    end

    def websocket_connection(request)
      Tipi::Websocket.new(@conn, request.headers)
    end

    def scheme_from_connection
      @conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
    end
    
    # response API

    CRLF = "\r\n"    
    CRLF_ZERO_CRLF_CRLF = "\r\n0\r\n\r\n"

    # Sends response including headers and body. Waits for the request to complete
    # if not yet completed. The body is sent using chunked transfer encoding.
    # @param request [Qeweney::Request] HTTP request
    # @param body [String] response body
    # @param headers
    def respond(request, body, headers)
      formatted_headers = format_headers(headers, body, false)
      request.tx_incr(formatted_headers.bytesize + (body ? body.bytesize : 0))
      if body
        @conn.write(formatted_headers, body)
      else
        @conn.write(formatted_headers)
      end
    end

    def respond_from_io(request, io, headers, chunk_size = 2**14)
      formatted_headers = format_headers(headers, true, true)
      request.tx_incr(formatted_headers.bytesize)
      
      # assume chunked encoding
      Thread.current.backend.splice_chunks(
        io,
        @conn,
        formatted_headers,
        "0\r\n\r\n",
        ->(len) { "#{len.to_s(16)}\r\n" },
        "\r\n",
        chunk_size
      )
    end

    # Sends response headers. If empty_response is truthy, the response status
    # code will default to 204, otherwise to 200.
    # @param request [Qeweney::Request] HTTP request
    # @param headers [Hash] response headers
    # @param empty_response [boolean] whether a response body will be sent
    # @param chunked [boolean] whether to use chunked transfer encoding
    # @return [void]
    def send_headers(request, headers, empty_response: false, chunked: true)
      formatted_headers = format_headers(headers, !empty_response, http1_1?(request) && chunked)
      request.tx_incr(formatted_headers.bytesize)
      @conn.write(formatted_headers)
    end

    def http1_1?(request)
      request.headers[':protocol'] == 'http/1.1'
    end
    
    # Sends a response body chunk. If no headers were sent, default headers are
    # sent using #send_headers. if the done option is true(thy), an empty chunk
    # will be sent to signal response completion to the client.
    # @param request [Qeweney::Request] HTTP request
    # @param chunk [String] response body chunk
    # @param done [boolean] whether the response is completed
    # @return [void]
    def send_chunk(request, chunk, done: false)
      data = +''
      data << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n" if chunk
      data << "0\r\n\r\n" if done
      return if data.empty?

      request.tx_incr(data.bytesize)
      @conn.write(data)
    end
    
    def send_chunk_from_io(request, io, r, w, chunk_size)
      len = w.splice(io, chunk_size)
      if len > 0
        Thread.current.backend.chain(
          [:write, @conn, "#{len.to_s(16)}\r\n"],
          [:splice, r, @conn, len],
          [:write, @conn, "\r\n"]
        )
      else
        @conn.write("0\r\n\r\n")
      end
      len
    end

    # Finishes the response to the current request. If no headers were sent,
    # default headers are sent using #send_headers.
    # @return [void]
    def finish(request)
      request.tx_incr(5)
      @conn << "0\r\n\r\n"
    end
    
    def close
      @conn.shutdown if @conn.respond_to?(:shutdown) rescue nil
      @conn.close
    end
    
    private

    INTERNAL_HEADER_REGEXP = /^:/.freeze

    # Formats response headers into an array. If empty_response is true(thy),
    # the response status code will default to 204, otherwise to 200.
    # @param headers [Hash] response headers
    # @param body [boolean] whether a response body will be sent
    # @param chunked [boolean] whether to use chunked transfer encoding
    # @return [String] formatted response headers
    def format_headers(headers, body, chunked)
      status = headers[':status']
      status ||= (body ? Qeweney::Status::OK : Qeweney::Status::NO_CONTENT)
      lines = format_status_line(body, status, chunked)
      headers.each do |k, v|
        next if k =~ INTERNAL_HEADER_REGEXP
        
        collect_header_lines(lines, k, v)
      end
      lines << CRLF
      lines
    end
    
    def format_status_line(body, status, chunked)
      if !body
        empty_status_line(status)
      else
        with_body_status_line(status, body, chunked)
      end
    end
    
    def empty_status_line(status)
      if status == 204
        +"HTTP/1.1 #{status}\r\n"
      else
        +"HTTP/1.1 #{status}\r\nContent-Length: 0\r\n"
      end
    end
    
    def with_body_status_line(status, body, chunked)
      if chunked
        +"HTTP/1.1 #{status}\r\nTransfer-Encoding: chunked\r\n"
      else
        +"HTTP/1.1 #{status}\r\nContent-Length: #{body.is_a?(String) ? body.bytesize : body.to_i}\r\n"
      end
    end

    def collect_header_lines(lines, key, value)
      if value.is_a?(Array)
        value.inject(lines) { |_, item| lines << "#{key}: #{item}\r\n" }
      else
        lines << "#{key}: #{value}\r\n"
      end
    end
  end
end
