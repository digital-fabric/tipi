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

      old_app = app
      app = proc do |req|
        conn = req.adapter.conn
        req.headers[':peer'] = conn.peeraddr(false)[2]
        req.headers[':scheme'] ||= conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
        old_app.(req)
      end

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
          rescue => e
            puts "Uncaught error in HTTP listener: #{e.inspect}"
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
        }
      
        puts "Listening for HTTPS on localhost:#{https_port}"
        server = Polyphony::Net.tcp_listen('0.0.0.0', https_port, opts)
        loop do
          socket = server.accept
          start_https_connection_fiber(socket, ctx, opts, app)
        rescue Polyphony::BaseException
          raise
        rescue OpenSSL::SSL::SSLError, SystemCallError, TypeError
          # ignore
        rescue Exception => e
          puts "HTTPS listener uncaught exception: #{e.inspect}"
        end
      ensure
        server.close
      end

      Fiber.await(http_listener, https_listener)
    end

    def start_https_connection_fiber(socket, ctx, opts, app)
      spin do
        client = OpenSSL::SSL::SSLSocket.new(socket, ctx)
        client.sync_close = true

        state = {}
        accept_thread = Thread.new do
          client.accept
          state[:result] = :ok
        rescue Exception => e
          state[:result] = e
        end
        move_on_after(30) { accept_thread.join }
        case state[:result]
        when Exception
          puts "Exception in SSL handshake: #{state[:result].inspect}"
          next
        when :ok
          # ok, continue
        else
          accept_thread.orig_kill rescue nil
          puts "Accept thread failed to complete SSL handshake"
        end

        Tipi.client_loop(client, opts, &app)
      rescue => e
        puts "Uncaught error in HTTPS connection fiber: #{e.inspect} bt: #{e.backtrace.inspect}"
      ensure
        (client ? client.close : socket.close) rescue nil
      end
    end
  end
end
