# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'localhost/authority'

::Exception.__disable_sanitized_backtrace__ = true

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
}

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'

ctx = authority.server_context
server = Polyphony::Net.tcp_listen('0.0.0.0', 1234, opts)
loop do
  socket = server.accept
  client = OpenSSL::SSL::SSLSocket.new(socket, ctx)
  client.sync_close = true
  spin do
    state = {}
    accept_thread = Thread.new do
      puts "call client accept"
      client.accept
      state[:result] = :ok
    rescue Exception => e
      puts error: e
      state[:result] = e
    end
    "wait for accept thread"
    accept_thread.join
    "accept thread done"
    if state[:result].is_a?(Exception)
      puts "Exception in SSL handshake: #{state[:result].inspect}"
      next
    end
    Tipi.client_loop(client, opts) do |req|
      p path: req.path
      if req.path == '/stream'
        req.send_headers('Foo' => 'Bar')
        sleep 0.5
        req.send_chunk("foo\n")
        sleep 0.5
        req.send_chunk("bar\n", done: true)
      elsif req.path == '/upload'
        body = req.read
        req.respond("Body: #{body.inspect} (#{body.bytesize} bytes)")
      else
        req.respond("Hello world!\n")
      end
    end
  ensure
    client ? client.close : socket.close
  end
end
