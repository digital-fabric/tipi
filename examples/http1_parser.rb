# frozen_string_literal: true

require 'polyphony'
require_relative '../lib/tipi_ext'

i, o = IO.pipe

f = spin do
  parser = Tipi::HTTP1Parser.new(i)
  while true
    headers = parser.parse_headers
    break unless headers
    puts '*' * 40
    p headers

    # puts '-' * 40
    # body = parser.read_body
  end
end

o << "post /?q=time&blah=blah HTTP/1\r\nHost: dev.realiteq.net\r\n\r\n"

o << "get /?q=time HTTP/1.1\r\n\r\n"

o << "get /?q=time HTTP/1.1\r\nCookie: foo\r\nCookie: bar\r\n\r\n"

o.close
f.await
