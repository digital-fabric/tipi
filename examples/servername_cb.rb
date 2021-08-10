# frozen_string_literal: true

require 'openssl'
require 'fiber'

ctx = OpenSSL::SSL::SSLContext.new

f = Fiber.new { |peer| loop { p peer: peer; _name, peer = peer.transfer nil } }
ctx.servername_cb = proc { |_socket, name|
  p servername_cb: name
  f.transfer([name, Fiber.current]).tap { |r| p result: r }
}

socket = Socket.new(:INET, :STREAM).tap do |s|
  s.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
  s.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, 1)
  s.bind(Socket.sockaddr_in(12345, '0.0.0.0'))
  s.listen(Socket::SOMAXCONN)
end
server = OpenSSL::SSL::SSLServer.new(socket, ctx)

Thread.new do
  sleep 0.5
  socket = TCPSocket.new('127.0.0.1', 12345)
  client = OpenSSL::SSL::SSLSocket.new(socket)
  client.hostname = 'example.com'
  p client: client
  client.connect
rescue => e
  p client_error: e
end

while true
  conn = server.accept
  p accepted: conn
  break
end
