# frozen_string_literal: true

require_relative './rack_adapter'
require_relative './http1_adapter'
require_relative './http2_adapter'

module Tipi
  class DefaultHandler
    def initialize(config)
      @config = config

      app_path = ARGV.first || './config.ru'
      @app = Tipi::RackAdapter.load(app_path)
    end

    def call(socket)
      socket.no_delay if socket.respond_to?(:no_delay)
      adapter = protocol_adapter(socket, {})
      adapter.each(&@app)
    ensure
      socket.close
    end

    ALPN_PROTOCOLS = %w[h2 http/1.1].freeze
    H2_PROTOCOL = 'h2'

    def protocol_adapter(socket, opts)
      use_http2 = socket.respond_to?(:alpn_protocol) &&
                  socket.alpn_protocol == H2_PROTOCOL

      klass = use_http2 ? HTTP2Adapter : HTTP1Adapter
      klass.new(socket, opts)
    end
  end
end
