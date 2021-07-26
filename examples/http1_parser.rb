# frozen_string_literal: true

require 'polyphony'
require_relative '../lib/tipi_ext'

i, o = IO.pipe

module ::Kernel
  def trace(*args)
    STDOUT.orig_write(format_trace(args))
  end

  def format_trace(args)
    if args.first.is_a?(String)
      if args.size > 1
        format("%s: %p\n", args.shift, args)
      else
        format("%s\n", args.first)
      end
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end
end

f = spin do
  parser = Tipi::HTTP1Parser.new(i)
  while true
    trace '*' * 40
    headers = parser.parse_headers
    break unless headers
    trace headers

    body = parser.read_body(headers)
    trace "body: #{body ? body.bytesize : 0} bytes"
  end
end

o << "GET /a HTTP/1.1\r\n\r\n"
o << "GET /b HTTP/1.1\r\n\r\n"

# o << "GET / HTTP/1.1\r\nHost: localhost:10080\r\nUser-Agent: curl/7.74.0\r\nAccept: */*\r\n\r\n"

# o << "post /?q=time&blah=blah HTTP/1\r\nHost: dev.realiteq.net\r\n\r\n"

# data = " " * 4000000
# o << "get /?q=time HTTP/1.1\r\nContent-Length: #{data.bytesize}\r\n\r\n#{data}"

# o << "get /?q=time HTTP/1.1\r\nCookie: foo\r\nCookie: bar\r\n\r\n"

# o.close
 
f.await
