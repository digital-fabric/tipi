# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'localhost/authority'

::Exception.__disable_sanitized_backtrace__ = true

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: authority.server_context
}

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
Tipi.serve('0.0.0.0', 1234, opts) do |req|
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
  # req.send_headers
  # req.send_chunk("Method: #{req.method}\n")
  # req.send_chunk("Path: #{req.path}\n")
  # req.send_chunk("Query: #{req.query.inspect}\n", done: true)
end
