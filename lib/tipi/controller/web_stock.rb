# frozen_string_literal: true

require 'ever'
require 'localhost/authority'
require 'http/parser'
require 'qeweney'
require 'tipi/rack_adapter'

module Tipi
  class Listener
    def initialize(server, &handler)
      @server = server
      @handler = handler
    end

    def accept
      socket, _addrinfo = @server.accept
      @handler.call(socket)
    end
  end

  class Connection
    def io_ready
      raise NotImplementedError
    end
  end

  class HTTP1Connection < Connection
    attr_reader :io

    def initialize(io, evloop, &app)
      @io = io
      @evloop = evloop
      @parser = Http::Parser.new(self)
      @app = app
      setup_read_request
    end

    def setup_read_request
      @request_complete = nil
      @request = nil
      @response_buffer = nil
    end

    def on_headers_complete(headers)
      headers = normalize_headers(headers)
      headers[':path'] = @parser.request_url
      headers[':method'] = @parser.http_method.downcase
      scheme = (proto = headers['x-forwarded-proto']) ?
                proto.downcase : scheme_from_connection
      headers[':scheme'] = scheme
      @request = Qeweney::Request.new(headers, self)
    end

    def normalize_headers(headers)
      headers.each_with_object({}) do |(k, v), h|
        k = k.downcase
        hk = h[k]
        if hk
          hk = h[k] = [hk] unless hk.is_a?(Array)
          v.is_a?(Array) ? hk.concat(v) : hk << v
        else
          h[k] = v
        end
      end
    end

    def scheme_from_connection
      @io.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
    end

    def on_body(chunk)
      @request.buffer_body_chunk(chunk)
    end

    def on_message_complete
      @request_complete = true
    end

    def io_ready
      if !@request_complete
        handle_read_request
      else
        handle_write_response
      end
    end

    def handle_read_request
      result = @io.read_nonblock(16384, exception: false)
      case result
      when :wait_readable
        watch_io(false)
      when :wait_writable
        watch_io(true)
      when nil
        close_io
      else
        @parser << result
        if @request_complete
          handle_request
          # @response = handle_request(@request_headers, @request_body)
          # handle_write_response
        else
          watch_io(false)
        end
      end
    rescue HTTP::Parser::Error, SystemCallError, IOError
      close_io
    end

    def watch_io(rw)
      @evloop.watch_io(self, @io, rw, true)
      # @evloop.emit([:watch_io, self, @io, rw, true])
    end

    def close_io
      @evloop.emit([:close_io, self, @io])
    end

    def handle_request
      @app.call(@request)
      # req = Qeweney::Request.new(headers, self)
      # response_body = "Hello, world!"
      # "HTTP/1.1 200 OK\nContent-Length: #{response_body.bytesize}\n\n#{response_body}"
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
        handle_write(formatted_headers + body)
      else
        handle_write(formatted_headers)
      end
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
      handle_write(formatted_headers)
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
      handle_write(data)
    end

    # Finishes the response to the current request. If no headers were sent,
    # default headers are sent using #send_headers.
    # @return [void]
    def finish(request)
      request.tx_incr(5)
      handle_write("0\r\n\r\n")
    end

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

    def handle_write(data = nil)
      if data
        if @response_buffer
          @response_buffer << data
        else
          @response_buffer = +data
        end
      end

      result = @io.write_nonblock(@response_buffer, exception: false)
      case result
      when :wait_readable
        watch_io(false)
      when :wait_writable
        watch_io(true)
      when nil
        close_io
      else
        setup_read_request
        watch_io(false)
      end
    end
  end

  class Controller
    def initialize(opts)
      @opts = opts
      @path = File.expand_path(@opts['path'])
      @service = prepare_service
    end

    WORKER_COUNT_RANGE = (1..32).freeze

    def run
      worker_count = (@opts['workers'] || 1).to_i.clamp(WORKER_COUNT_RANGE)
      return run_worker if worker_count == 1

      supervise_workers(worker_count)
    end

  private

    def supervise_workers(worker_count)
      supervisor = spin do
        worker_count.times do
          pid = fork { run_worker }
          puts "Forked worker pid: #{pid}"
          Process.wait(pid)
          puts "Done worker pid: #{pid}"
        end
        # supervise(restart: :always)
      rescue Polyphony::Terminate
        # TODO: find out how Terminate can leak like that (it's supposed to be
        # caught in Fiber#run)
      end
      # trap('SIGTERM') { supervisor.terminate(true) }
      # trap('SIGINT') do
      #   trap('SIGINT') { exit! }
      #   supervisor.terminate(true)
      # end

      # supervisor.await
    end

    def run_worker
      @evloop = Ever::Loop.new
      start_server(@service)
      trap('SIGTERM') { @evloop.stop }
      trap('SIGINT') do
        trap('SIGINT') { exit! }
        @evloop.stop
      end
      run_evloop
    end

    def run_evloop
      @evloop.each do |event|
        case event
        when Listener
          event.accept
        when Connection
          event.io_ready
        when Array
          cmd, key, io, rw, oneshot = event
          case cmd
          when :watch_io
            @evloop.watch_io(key, io, rw, oneshot)
          when :close_io
            io.close
          end
        end
      end
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
      puts "Loading Rack app from #{@path}"
      app = Tipi::RackAdapter.load(@path)
      web_service(app)
    end

    def tipi_service
      puts "Loading Tipi app from #{@path}"
      require(@path)
      app = Object.send(:app)
      web_service(app)
    end

    def static_service
      puts "Serving static files from #{@path}"
      app = proc do |req|
        p req: req
        full_path = find_path(@path, req.path)
        if full_path
          req.serve_file(full_path)
        else
          req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
        end
      end
      web_service(app)
    end

    def web_service(app)
      app = add_connection_headers(app)

      prepare_listener(@opts['listen'], app)
    end

    def prepare_listener(spec, app)
      case spec.shift
      when 'http'
        case spec.size
        when 2
          host, port = spec
          port ||= 80
        when 1
          host = '0.0.0.0'
          port = spec.first || 80
        else
          raise "Invalid listener spec"
        end
        prepare_http_listener(port, app)
      when 'https'
        case spec.size
        when 2
          host, port = spec
          port ||= 80
        when 1
          host = 'localhost'
          port = spec.first || 80
        else
          raise "Invalid listener spec"
        end
        port ||= 443
        prepare_https_listener(host, port, app)
      when 'full'
        host, http_port, https_port = spec
        http_port ||= 80
        https_port ||= 443
        prepare_full_service_listeners(host, http_port, https_port, app)
      end
    end

    def prepare_http_listener(port, app)
      puts "Listening for HTTP on localhost:#{port}"

      proc do
        start_listener('HTTP', port) do |socket|
          start_client(socket, &app)
        end
      end
    end

    def start_client(socket, &app)
      conn = HTTP1Connection.new(socket, @evloop, &app)
      conn.watch_io(false)
    end

    LOCALHOST_REGEXP = /^(.+\.)?localhost$/.freeze

    def prepare_https_listener(host, port, app)
      localhost = host =~ LOCALHOST_REGEXP
      return prepare_localhost_https_listener(port, app) if localhost

      raise "No certificate found for #{host}"
      # TODO: implement loading certificate
    end

    def prepare_localhost_https_listener(port, app)
      puts "Listening for HTTPS on localhost:#{port}"

      authority = Localhost::Authority.fetch
      ctx = authority.server_context
      ctx.ciphers = 'ECDH+aRSA'
      Polyphony::Net.setup_alpn(ctx, Tipi::ALPN_PROTOCOLS)

      proc do
        https_listener = spin_accept_loop('HTTPS', port) do |socket|
          start_https_connection_fiber(socket, ctx, nil, app)
        rescue Exception => e
          puts "Exception in https_listener block: #{e.inspect}\n#{e.backtrace.inspect}"
        end
      end
    end

    def prepare_full_service_listeners(host, http_port, https_port, app)
      puts "Listening for HTTP on localhost:#{http_port}"
      puts "Listening for HTTPS on localhost:#{https_port}"

      redirect_host = (https_port == 443) ? host : "#{host}:#{https_port}"
      redirect_app = ->(r) { r.redirect("https://#{redirect_host}#{r.path}") }
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

    def start_listener(name, port, &block)
      host = '0.0.0.0'
      socket = ::Socket.new(:INET, :STREAM).tap do |s|
        s.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        s.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, 1)
        s.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [0, 0].pack('ii'))
        addr = ::Socket.sockaddr_in(port, host)
        s.bind(addr)
        s.listen(Socket::SOMAXCONN)
      end
      listener = Listener.new(socket, &block)
      @evloop.watch_io(listener, socket, false, false)
    end

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
    rescue Polyphony::BaseException
      raise
    rescue Exception => e
      p e
      e
    end

    def start_https_connection_fiber(socket, ctx, thread_pool, app)
      client = OpenSSL::SSL::SSLSocket.new(socket, ctx)
      client.sync_close = true

      result = thread_pool ?
        thread_pool.process { ssl_accept(client) } : ssl_accept(client)

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
      service.call
    end
  end
end
