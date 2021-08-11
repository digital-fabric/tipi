# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/acme'

::Exception.__disable_sanitized_backtrace__ = true

http_handler = ->(r) { r.redirect("https://#{r.host}#{r.path}") }
https_handler = ->(r) { r.respond('Hello, world!') }

ctx = OpenSSL::SSL::SSLContext.new
ctx.ciphers = 'ECDH+aRSA'
Polyphony::Net.setup_alpn(ctx, Tipi::ALPN_PROTOCOLS)

challenge_handler = Tipi::ACME::HTTPChallengeHandler.new
certificate_manager = Tipi::ACME::CertificateManager.new(
  master_ctx: ctx,
  store: Tipi::ACME::InMemoryCertificateStore.new,
  challenge_handler: challenge_handler
)

http_listener = spin do
  opts = {
    reuse_addr:   true,
    reuse_port:   true,
    dont_linger:  true,
  }
  puts 'Listening for HTTP on localhost:10080'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10080, opts)
  wrapped_handler = certificate_manager.challenge_routing_app(http_handler)
  server.accept_loop do |client|
    spin do
      Tipi.client_loop(client, opts, &wrapped_handler)
    end      
  end
  # Tipi.serve('0.0.0.0', 10080, opts, &http_handler)
end

https_listener = spin do
  opts = {
    reuse_addr:     true,
    reuse_port:     true,
    dont_linger:    true,
    secure_context: ctx,
  }

  puts 'Listening for HTTPS on localhost:10443'
  server = Polyphony::Net.tcp_listen('0.0.0.0', 10443, opts)
  loop do
    client = server.accept
    spin do
      Tipi.client_loop(client, opts) { |req| req.respond('Hello world') }
    end
  rescue OpenSSL::SSL::SSLError, SystemCallError => e
    p https_error: e
  end
rescue Exception => e
  p error: e
  p e.backtrace
  exit!
ensure
  server.close
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
