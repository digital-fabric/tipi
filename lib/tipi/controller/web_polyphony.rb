# frozen_string_literal: true

require 'tipi'

module Tipi
  class Controller
    def initialize(opts)
      @opts = opts
      @path = @opts['path']
    end

    def stop
      @server.terminate(true)
    end

    def run
      if File.file?(@path)
        start_app
      elsif File.directory?(@path)
        start_static_server
      else
        puts "Invalid path specified #{@path}"
        exit!
      end
      raise 'Server not started' unless @server
      @server.await
    end

    def start_app
      if File.extname(@path) == '.ru'
        start_rack_app
      else
        require(@path)
      end
    end

    def start_rack_app
      puts "Loading Rack app from #{File.expand_path(@path)}"
      app = Tipi::RackAdapter.load(@path)
      start_server(app)
    end

    def start_static_server
      app = proc do |req|
        full_path = find_path(@path, req.path)
        if full_path
          req.serve_file(full_path)
        else
          req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
        end
      end
      puts "Serving static files from #{File.expand_path(@path)}"
      start_server(app)
    end

    def start_server(app)
      @server = spin do
        full_service(&app)
        supervise(restart: :always)
      end
    end

    INVALID_PATH_REGEXP = /\/?(\.\.|\.)\//

    def find_path(base, path)
      p find_path: [base, path]
      return nil if path =~ INVALID_PATH_REGEXP

      full_path = File.join(base, path)
      return full_path if File.file?(full_path)
      return find_path(full_path, 'index') if File.directory?(full_path)

      qualified = "#{full_path}.html"
      return qualified if File.file?(qualified)

      nil
    end

    SOCKET_OPTS = {
      reuse_addr:   true,
      reuse_port:   true,
      dont_linger:  true,
    }.freeze

    def full_service(http_port: 10080, https_port: 10443,
                     certificate_store: default_certificate_store, app: nil,
                     &block)
      app ||= block
      raise "No app given" unless app

      redirect_app = ->(r) { r.redirect("https://#{r.host}#{r.path}") }
      app = add_connection_headers(app)
    
      ctx = OpenSSL::SSL::SSLContext.new
      # ctx.ciphers = 'ECDH+aRSA'
      Polyphony::Net.setup_alpn(ctx, Tipi::ALPN_PROTOCOLS)
    
      challenge_handler = Tipi::ACME::HTTPChallengeHandler.new
      certificate_manager = Tipi::ACME::CertificateManager.new(
        master_ctx: ctx,
        store: certificate_store,
        challenge_handler: challenge_handler
      )

      http_app = certificate_manager.challenge_routing_app(redirect_app)

      http_listener = spin_accept_loop('HTTP', http_port) do |socket|
        Tipi.client_loop(socket, @opts, &http_app)
      end

      https_listener = spin_accept_loop('HTTPS', https_port) do |socket|
        start_https_connection_fiber(socket, ctx, @opts, &app)
      end

      [http_listener, https_listener]
    end

    def spin_accept_loop(name, port)
      spin do
        puts "Listening for #{name} on localhost:#{port}"
        server = Polyphony::Net.tcp_listen('0.0.0.0', port, SOCKET_OPTS)
        loop do
          socket = server.accept
          spin do
            yield socket
          rescue Polyphony::BaseException
            raise
          rescue Exception => e
              puts "Uncaught error in HTTP listener: #{e.inspect}"
          end
        rescue Polyphony::BaseException
          raise
        rescue Exception => e
          puts "#{name} listener uncaught exception: #{e.inspect}"
        end
      ensure
        puts "spin_accept_loop ensure graceful: #{Fiber.current.graceful_shutdown?.inspect}"
        finalize_listener(server) if server
      end
    end

    def finalize_listener(server)
      fiber  = Fiber.current
      gracefully_terminate_conections(fiber) if fiber.graceful_shutdown?
      server.close
    end

    def gracefully_terminate_conections(fiber)
      supervisor = spin { supervise }.detach
      fiber.attach_all_children_to(supervisor)

      # terminating the supervisor will 
      supervisor.terminate(true)
    end

    def add_connection_headers(app)
      proc do |req|
        conn = req.adapter.conn
        req.headers[':peer'] = conn.peeraddr(false)[2]
        req.headers[':scheme'] ||= conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
        app.(req)
      end
    end

    def start_https_connection_fiber(socket, ctx, opts, &app)
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

    CERTIFICATE_STORE_DEFAULT_DIR = File.expand_path('~/.tipi')
    CERTIFICATE_STORE_DEFAULT_DB_PATH = File.join(
      CERTIFICATE_STORE_DEFAULT_DIR, 'certificates.db'
    )

    def default_certificate_store
      FileUtils.mkdir(CERTIFICATE_STORE_DEFAULT_DIR) rescue nil
      Tipi::ACME::SQLiteCertificateStore.new(CERTIFICATE_STORE_DEFAULT_DB_PATH)
    end
  end
end
