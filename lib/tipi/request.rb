# frozen_string_literal: true

require 'uri'
require 'escape_utils'

module Tipi
  module InfoInstanceMethods
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
      @method ||= @headers[':method'].downcase
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

  module InfoClassMethods
    def parse_form_data(body, headers)
      case (content_type = headers['content-type'])
      when /multipart\/form\-data; boundary=([^\s]+)/
        boundary = "--#{Regexp.last_match(1)}"
        parse_multipart_form_data(body, boundary)
      when 'application/x-www-form-urlencoded'
        parse_urlencoded_form_data(body)
      else
        raise "Unsupported form data content type: #{content_type}"
      end
    end

    def parse_multipart_form_data(body, boundary)
      parts = body.split(boundary)
      parts.each_with_object({}) do |p, h|
        next if p.empty? || p == "--\r\n"

        # remove post-boundary \r\n
        p.slice!(0, 2)
        parse_multipart_form_data_part(p, h)
      end
    end

    def parse_multipart_form_data_part(part, hash)
      body, headers = parse_multipart_form_data_part_headers(part)
      disposition = headers['content-disposition'] || ''

      name = (disposition =~ /name="([^"]+)"/) ? Regexp.last_match(1) : nil
      filename = (disposition =~ /filename="([^"]+)"/) ? Regexp.last_match(1) : nil

      if filename
        hash[name] = { filename: filename, content_type: headers['content-type'], data: body }
      else
        hash[name] = body
      end
    end

    def parse_multipart_form_data_part_headers(part)
      headers = {}
      while true
        idx = part.index("\r\n")
        break unless idx

        header = part[0, idx]
        part.slice!(0, idx + 2)
        break if header.empty?

        next unless header =~ /^([^\:]+)\:\s?(.+)$/
        
        headers[Regexp.last_match(1).downcase] = Regexp.last_match(2)
      end
      # remove trailing \r\n
      part.slice!(part.size - 2, 2)
      [part, headers]
    end

    PARAMETER_RE = /^(.+)=(.*)$/.freeze
    MAX_PARAMETER_NAME_SIZE = 256
    MAX_PARAMETER_VALUE_SIZE = 2**20 # 1MB

    def parse_urlencoded_form_data(body)
      body.force_encoding(UTF_8) unless body.encoding == Encoding::UTF_8
      body.split('&').each_with_object({}) do |i, m|
        raise 'Invalid parameter format' unless i =~ PARAMETER_RE
  
        k = Regexp.last_match(1)
        raise 'Invalid parameter size' if k.size > MAX_PARAMETER_NAME_SIZE
  
        v = Regexp.last_match(2)
        raise 'Invalid parameter size' if v.size > MAX_PARAMETER_VALUE_SIZE
  
        m[EscapeUtils.unescape_uri(k)] = EscapeUtils.unescape_uri(v)
      end
    end
  end

  module RoutingInstanceMethods
    def route(&block)
      res = catch(:stop) { yield self }
      return if res == :found
  
      respond(nil, ':status' => 404)
    end

    @@regexp_cache = {}
  
    def on(route, &block)
      @__routing_path__ ||= path

      regexp = (@@regexp_cache[route] ||= /^\/#{route}(\/.*)?/)
      return unless @__routing_path__ =~ regexp
  
      @__routing_path__ = Regexp.last_match(1)
      catch(:stop, &block)
      throw :stop, :found
    end

    def root(&block)
      return unless path == '/'

      catch(:stop, &block)
      throw :stop, :found
    end
  
    def get(route = nil, &block)
      return unless method == 'get'
  
      on(route, &block)
    end
  
    def post(route = nil, &block)
      return unless method == 'post'
  
      on(route, &block)
    end
  end

  module ResponseInstanceMethods
    def redirect(url)
      respond(nil, ':status' => 302, 'Location' => url)
    end
  end

  # HTTP request
  class Request
    include InfoInstanceMethods
    extend InfoClassMethods

    include RoutingInstanceMethods
    include ResponseInstanceMethods

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