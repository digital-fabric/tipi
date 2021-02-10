# frozen_string_literal: true

require 'polyphony'
require_relative './tipi/http1_adapter'
require_relative './tipi/http2_adapter'
require_relative './tipi/configuration'

module Tipi
  ALPN_PROTOCOLS = %w[h2 http/1.1].freeze
  H2_PROTOCOL = 'h2'
  
  class << self
    def serve(host, port, opts = {}, &handler)
      opts[:alpn_protocols] = ALPN_PROTOCOLS
      server = Polyphony::Net.tcp_listen(host, port, opts)
      accept_loop(server, opts, &handler)
    ensure
      server&.close
    end
    
    def listen(host, port, opts = {})
      opts[:alpn_protocols] = ALPN_PROTOCOLS
      Polyphony::Net.tcp_listen(host, port, opts).tap do |socket|
        socket.define_singleton_method(:each) do |&block|
          ::Tipi.accept_loop(socket, opts, &block)
        end
      end
    end
    
    def accept_loop(server, opts, &handler)
      server.accept_loop do |client|
        spin { client_loop(client, opts, &handler) }
      rescue OpenSSL::SSL::SSLError
        # disregard
      end
    end
    
    def client_loop(client, opts, &handler)
      client.no_delay if client.respond_to?(:no_delay)
      adapter = protocol_adapter(client, opts)
      adapter.each(&handler)
    ensure
      client.close rescue nil
    end
    
    def protocol_adapter(socket, opts)
      use_http2 = socket.respond_to?(:alpn_protocol) &&
                  socket.alpn_protocol == H2_PROTOCOL
      klass = use_http2 ? HTTP2Adapter : HTTP1Adapter
      klass.new(socket, opts)
    end

    def route(&block)
      proc { |req| req.route(&block) }
    end
  end
end
