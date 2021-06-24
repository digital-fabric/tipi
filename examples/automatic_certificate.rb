# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'openssl'
require 'acme-client'

# ::Exception.__disable_sanitized_backtrace__ = true

class CertificateManager
  def initialize(store:, challenge_handler:)
    @store = store
    @challenge_handler = challenge_handler
    @workers = {}
    @contexts = {}
  end

  def [](name)
    worker = worker_for_name(name)
    p worker: worker
  
    worker << Fiber.current
    # cancel_after(30) { receive }
    receive.tap { |ctx| p got_ctx: ctx }
  rescue Exception => e
    p e
    puts e.backtrace.join("\n")
    nil
  end
  
  def worker_for_name(name)
    @workers[name] ||= spin { worker_loop(name) }
  end
  
  def worker_loop(name)
    while (client = receive)
      puts "get request for #{name} from #{client.inspect}"
      ctx = get_context(name)
      client << ctx rescue nil
    end
  end

  def get_context(name)
    @contexts[name] ||= setup_context(name)
  end

  CERTIFICATE_REGEXP = /(-----BEGIN CERTIFICATE-----\n[^-]+-----END CERTIFICATE-----\n)/.freeze

  def setup_context(name)
    certificate = get_certificate(name)
    ctx = OpenSSL::SSL::SSLContext.new
    chain = certificate.scan(CERTIFICATE_REGEXP).map { |p|  OpenSSL::X509::Certificate.new(p.first) }
    cert = chain.shift
    puts "Certificate expires: #{cert.not_after.inspect}"
    ctx.add_certificate(cert, private_key, chain)
    Polyphony::Net.setup_alpn(ctx, Tipi::ALPN_PROTOCOLS)
    ctx
  end
  
  def get_certificate(name)
    @store[name] ||= provision_certificate(name)
  end

  def private_key
    @private_key ||= OpenSSL::PKey::RSA.new(4096)
  end

  ACME_DIRECTORY = 'https://acme-staging-v02.api.letsencrypt.org/directory'

  def acme_client
    @acme_client ||= setup_acme_client
  end

  def setup_acme_client
    client = Acme::Client.new(
      private_key: private_key,
      directory: ACME_DIRECTORY
    )
    p client: client
    account = client.new_account(
      contact: 'mailto:info@noteflakes.com',
      terms_of_service_agreed: true
    )
    p account: account.kid
    client
  end

  def provision_certificate(name)
    order = acme_client.new_order(identifiers: [name])
    p order: true
    authorization = order.authorizations.first
    p authorization: authorization
    challenge = authorization.http
    p challenge: challenge
  
    @challenge_handler.add(challenge)
    challenge.request_validation
    p challenge_status: challenge.status
    while challenge.status == 'pending'
      sleep(1)
      challenge.reload
      p challenge_status: challenge.status
    end
  
    csr = Acme::Client::CertificateRequest.new(private_key: @private_key, subject: { common_name: name })
    p csr: csr
    order.finalize(csr: csr)
    p order_status: order.status
    while order.status == 'processing'
      sleep(1)
      order.reload
      p order_status: order.status
    end
    order.certificate.tap { |c| p certificate: c } # => PEM-formatted certificate
  end
end

class AcmeHTTPChallengeHandler
  def initialize
    @challenges = {}
  end

  def add(challenge)
    path = "/.well-known/acme-challenge/#{challenge.token}"
    @challenges[path] = challenge
  end

  def call(req)
    # handle incoming request
    challenge = @challenges[req.path]
    return req.respond(nil, ':status' => 400) unless challenge

    req.respond(challenge.file_content, 'content-type' => challenge.content_type)
    @challenges.delete(req.path)
  end
end

challenge_handler = AcmeHTTPChallengeHandler.new
certificate_manager = CertificateManager.new(
  store: {},
  challenge_handler: challenge_handler
)

http_handler = Tipi.route do |r|
  r.on('/.well-known/acme-challenge') { challenge_handler.call(r) }
  r.default { r.redirect "https://#{r.host}#{r.path}" }
end

https_handler = ->(r) { r.respond('Hello, world!') }

http_listener = spin do
  opts = {
    reuse_addr:  true,
    dont_linger: true,
  }
  puts 'Listening for HTTP on localhost:10080'
  Tipi.serve('0.0.0.0', 10080, opts, &http_handler)
end

https_listener = spin do
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.servername_cb = proc { |_, name| p name: name; certificate_manager[name] }
  opts = {
    reuse_addr:     true,
    dont_linger:    true,
    secure_context: ctx,
    alpn_protocols: Tipi::ALPN_PROTOCOLS
  }

  puts 'Listening for HTTPS on localhost:10443'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10443, opts)
  server.accept_loop do |client|
    spin do
      service.incr_connection_count
      Tipi.client_loop(client, opts) { |req| service.http_request(req) }
    ensure
      service.decr_connection_count
    end
  rescue Exception => e
    puts "HTTPS accept_loop error: #{e.inspect}"
    puts e.backtrace.join("\n")
  end
end

begin
  Fiber.await(http_listener, https_listener)
rescue Interrupt
  puts "Got SIGINT, terminating"
rescue Exception => e
  puts '*' * 40
  p e
  puts e.backtrace.join("\n")
end
