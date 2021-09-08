# frozen_string_literal: true

require 'tipi'

module Tipi
  class Controller
    def initialize(opts)
      @opts = opts
      @path = @opts['path']
      @service = prepare_service

      p opts: opts
    end

    WORKER_COUNT_RANGE = (1..32).freeze

    def run
      puts "Listening for HTTP on localhost:10080"
      puts "Listening for HTTPS on localhost:10443"

      worker_count = (@opts['workers'] || 1).to_i.clamp(WORKER_COUNT_RANGE)
      return run_worker if worker_count == 1

      supervise_workers(worker_count)
    end

  private

    def supervise_workers(worker_count)
      supervisor = spin do
        worker_count.times do
          spin do
            pid = Polyphony.fork { run_worker }
            puts "Forked worker pid: #{pid}"
            Polyphony.backend_waitpid(pid)
            puts "Done worker pid: #{pid}"
          end
        end
        supervise(restart: :always)
      rescue Polyphony::Terminate
        # TODO: find out how Terminate can leak like that (it's supposed to be
        # caught in Fiber#run)
      end
      trap('SIGTERM') { supervisor.terminate(true) }
      trap('SIGINT') do
        trap('SIGINT') { exit! }
        supervisor.terminate(true)
      end

      supervisor.await
    rescue Polyphony::Terminate
      # TODO: find out how Terminate can leak etc.
    end

    def run_worker
      server = start_server(@service)
      trap('SIGTERM') { server&.terminate(true) }
      trap('SIGINT') do
        trap('SIGINT') { exit! }
        server&.terminate(true)
      end
      raise 'Server not started' unless server
      server.await
    rescue Polyphony::Terminate
      # TODO: find out why this exception leaks from the server fiber
      # ignore
    end

    def prepare_service
      if File.file?(@path)
        File.extname(@path) == '.ru' ? rack_service : tipi_service
      elsif File.directory?(@path)
        static_service
      else
        raise "Invalid path specified #{@path}"
      end
    end

    def start_app
      if File.extname(@path) == '.ru'
        start_rack_app
      else
        require(@path)
      end
    end

    def rack_service
      puts "Loading Rack app from #{File.expand_path(@path)}"
      app = Tipi::RackAdapter.load(@path)
      web_service(&app)
    end

    def tipi_service
      require(@path)
      proc { spin { Object.run } }
    end

    def static_service
      puts "Serving static files from #{File.expand_path(@path)}"
      app = proc do |req|
        full_path = find_path(@path, req.path)
        if full_path
          req.serve_file(full_path)
        else
          req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
        end
      end
      web_service(&app)
    end

    def web_service(http_port: 10080, https_port: 10443,
                    app: nil, &block)
      app ||= block
      raise "No app given" unless app

      redirect_app = ->(r) { r.redirect("https://#{r.host}#{r.path}") }
      app = add_connection_headers(app)

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ciphers = 'ECDH+aRSA'
      Polyphony::Net.setup_alpn(ctx, Tipi::ALPN_PROTOCOLS)
  
      certificate_store = create_certificate_store

      proc do
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

        ssl_accept_thread_pool = Polyphony::ThreadPool.new(4)
  
        https_listener = spin_accept_loop('HTTPS', https_port) do |socket|
          start_https_connection_fiber(socket, ctx, ssl_accept_thread_pool, app)
        rescue Exception => e
          puts "Exception in https_listener block: #{e.inspect}\n#{e.backtrace.inspect}"
        end
      end
    end

    INVALID_PATH_REGEXP = /\/?(\.\.|\.)\//

    def find_path(base, path)
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

    def spin_accept_loop(name, port, &block)
      spin do
        server = Polyphony::Net.tcp_listen('0.0.0.0', port, SOCKET_OPTS)
        loop do
          socket = server.accept
          spin_connection_handler(name, socket, block)
        rescue Polyphony::BaseException => e
          raise
        rescue Exception => e
          puts "#{name} listener uncaught exception: #{e.inspect}"
        end
      ensure
        finalize_listener(server) if server
      end
    end

    def spin_connection_handler(name, socket, block)
      spin do
        block.(socket)
      rescue Polyphony::BaseException
        raise
      rescue Exception => e
        puts "Uncaught error in #{name} handler: #{e.inspect}"
        p e.backtrace
      end
    end

    def finalize_listener(server)
      fiber  = Fiber.current
      gracefully_terminate_conections(fiber) if fiber.graceful_shutdown?
      server.close
    rescue Polyphony::BaseException
      raise
    rescue Exception => e
      trace "Exception in finalize_listener: #{e.inspect}"
    end

    def gracefully_terminate_conections(fiber)
      supervisor = spin { supervise }.detach
      fiber.attach_all_children_to(supervisor)

      # terminating the supervisor will 
      supervisor.terminate(true)
    end

    def add_connection_headers(app)
      app
      # proc do |req|
      #   conn = req.adapter.conn
      #   # req.headers[':peer'] = conn.peeraddr(false)[2]
      #   req.headers[':scheme'] ||= conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
      #   app.(req)
      # end
    end

    def ssl_accept(client)
      client.accept
      true
    rescue Exception => e
      e
    end

    def start_https_connection_fiber(socket, ctx, thread_pool, app)
      client = OpenSSL::SSL::SSLSocket.new(socket, ctx)
      client.sync_close = true

      result = thread_pool.process { ssl_accept(client) }
      if result.is_a?(Exception)
        puts "Exception in SSL handshake: #{result.inspect}"
        return
      end

      Tipi.client_loop(client, @opts, &app)
    rescue => e
      puts "Uncaught error in HTTPS connection fiber: #{e.inspect} bt: #{e.backtrace.inspect}"
    ensure
      (client ? client.close : socket.close) rescue nil
    end

    CERTIFICATE_STORE_DEFAULT_DIR = File.expand_path('~/.tipi').freeze
    CERTIFICATE_STORE_DEFAULT_DB_PATH = File.join(
      CERTIFICATE_STORE_DEFAULT_DIR, 'certificates.db').freeze

    def create_certificate_store
      FileUtils.mkdir(CERTIFICATE_STORE_DEFAULT_DIR) rescue nil
      Tipi::ACME::SQLiteCertificateStore.new(CERTIFICATE_STORE_DEFAULT_DB_PATH)
    end

    def start_server(service)
      spin do
        service.call
        supervise(restart: :always)
      end
    end
  end
end
