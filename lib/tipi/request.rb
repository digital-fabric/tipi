# frozen_string_literal: true

require 'uri'

module Tipi
  module RequestInfo
    def host
      @headers['host']
    end

    def connection
      @headers['connection']
    end

    def upgrade_protocol
      connection == 'upgrade' && @headers['upgrade']&.downcase
    end

    def protocol
      @protocol ||= @adapter.protocol
    end
    
    def method
      @method ||= @headers[':method']
    end
    
    def scheme
      @scheme ||= @headers[':scheme']
    end
    
    def uri
      @uri ||= URI.parse(@headers[':path'] || '')
    end
    
    def path
      @path ||= uri.path
    end
    
    def query_string
      @query_string ||= uri.query
    end
    
    def query
      return @query if @query
      
      @query = (q = uri.query) ? split_query_string(q) : {}
    end
    
    def split_query_string(query)
      query.split('&').each_with_object({}) do |kv, h|
        k, v = kv.split('=')
        h[k.to_sym] = URI.decode_www_form_component(v)
      end
    end

    def request_id
      @headers['x-request-id']
    end

    def forwarded_for
      @headers['x-forwarded-for']
    end
  end

  # HTTP request
  class Request
    include RequestInfo

    attr_reader :headers, :adapter
    attr_accessor :__next__
    
    def initialize(headers, adapter)
      @headers  = headers
      @adapter  = adapter
    end
        
    def buffer_body_chunk(chunk)
      @buffered_body_chunks ||= []
      @buffered_body_chunks << chunk
    end

    def next_chunk
      if @buffered_body_chunks
        chunk = @buffered_body_chunks.shift
        @buffered_body_chunks = nil if @buffered_body_chunks.empty?
        return chunk
      end

      @message_complete ? nil : @adapter.get_body_chunk
    end
    
    def each_chunk
      if @buffered_body_chunks
        while (chunk = @buffered_body_chunks.shift)
          yield chunk
        end
        @buffered_body_chunks = nil
      end
      while !@message_complete && (chunk = @adapter.get_body_chunk)
        yield chunk
      end
    end

    def complete!(keep_alive = nil)
      @message_complete = true
      @keep_alive = keep_alive
    end
    
    def complete?
      @message_complete
    end
    
    def consume
      @adapter.consume_request
    end
    
    def keep_alive?
      @keep_alive
    end
    
    def read
      buf = @buffered_body_chunks ? @buffered_body_chunks.join : nil
      while (chunk = @adapter.get_body_chunk)
        (buf ||= +'') << chunk
      end
      @buffered_body_chunks = nil
      buf
    end
    alias_method :body, :read
    
    def respond(body, headers = {})
      @adapter.respond(body, headers)
      @headers_sent = true
    end
    
    def send_headers(headers = {}, empty_response = false)
      return if @headers_sent
      
      @headers_sent = true
      @adapter.send_headers(headers, empty_response: empty_response)
    end
    
    def send_chunk(body, done: false)
      send_headers({}) unless @headers_sent
      
      @adapter.send_chunk(body, done: done)
    end
    alias_method :<<, :send_chunk
    
    def finish
      send_headers({}) unless @headers_sent
      
      @adapter.finish
    end

    def headers_sent?
      @headers_sent
    end
  end
end