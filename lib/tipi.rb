# frozen_string_literal: true

require 'polyphony'

require_relative './tipi/http1_adapter'
require_relative './tipi/http2_adapter'
require_relative './tipi/configuration'
require_relative './tipi/response_extensions'
require_relative './tipi/acme'

require 'qeweney/request'

class Qeweney::Request
  include Tipi::ResponseExtensions
end

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

    CERTIFICATE_STORE_DEFAULT_DIR = File.expand_path('~/.tipi')
    CERTIFICATE_STORE_DEFAULT_DB_PATH = File.join(
      CERTIFICATE_STORE_DEFAULT_DIR, 'certificates.db'
    )

    def default_certificate_store
      FileUtils.mkdir(CERTIFICATE_STORE_DEFAULT_DIR) rescue nil
      Tipi::ACME::SQLiteCertificateStore.new(CERTIFICATE_STORE_DEFAULT_DB_PATH)
    end

    def full_service(
      http_port: 10080,
      https_port: 10443,
      certificate_store: default_certificate_store,
      app: nil, &block
    )
      app ||= block
      raise "No app given" unless app

      http_handler = ->(r) { r.redirect("https://#{r.host}#{r.path}") }
    
      ctx = OpenSSL::SSL::SSLContext.new
      # ctx.ciphers = 'ECDH+aRSA'
      Polyphony::Net.setup_alpn(ctx, Tipi::ALPN_PROTOCOLS)
    
      challenge_handler = Tipi::ACME::HTTPChallengeHandler.new
      certificate_manager = Tipi::ACME::CertificateManager.new(
        master_ctx: ctx,
        store: certificate_store,
        challenge_handler: challenge_handler
      )
    
      http_listener = spin do
        opts = {
          reuse_addr:   true,
          reuse_port:   true,
          dont_linger:  true,
        }
        puts "Listening for HTTP on localhost:#{http_port}"
        server = Polyphony::Net.tcp_listen('0.0.0.0', http_port, opts)
        wrapped_handler = certificate_manager.challenge_routing_app(http_handler)
        server.accept_loop do |client|
          spin do
            Tipi.client_loop(client, opts, &wrapped_handler)
          end      
        end
      ensure
        server.close
      end
    
      https_listener = spin do
        opts = {
          reuse_addr:     true,
          reuse_port:     true,
          dont_linger:    true,
          secure_context: ctx,
        }
      
        puts "Listening for HTTPS on localhost:#{https_port}"
        server = Polyphony::Net.tcp_listen('0.0.0.0', https_port, opts)
        loop do
          client = server.accept
          spin do
            Tipi.client_loop(client, opts, &app)
          end
        rescue OpenSSL::SSL::SSLError, SystemCallError, TypeError => e
          p https_error: e
        end
      ensure
        server.close
      end

      Fiber.await(http_listener, https_listener)
    end
  end
end
