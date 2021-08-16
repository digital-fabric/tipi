# frozen_string_literal: true

require 'bundler/setup'

HTTP_REQUEST = "GET /foo HTTP/1.1\r\nHost: example.com\r\nAccept: */*\r\n\r\n"

def benchmark_other_http1_parser(iterations)
  STDOUT << "http_parser.rb: "
  require 'http_parser.rb'
  
  i, o = IO.pipe
  parser = Http::Parser.new
  done = false
  headers = nil
  parser.on_headers_complete = proc do |h|
    headers = h
    headers[':method'] = parser.http_method
    headers[':path'] = parser.request_url
    headers[':protocol'] = parser.http_version
  end
  parser.on_message_complete = proc { done = true }

  t0 = Time.now
  iterations.times do
    o << HTTP_REQUEST
    done = false
    while !done
      msg = i.readpartial(4096)
      parser << msg
    end
  end
  t1 = Time.now
  puts "#{iterations / (t1 - t0)} ips"
end

def benchmark_tipi_http1_parser(iterations)
  STDOUT << "tipi parser: "
  require_relative '../lib/tipi_ext'
  i, o = IO.pipe
  reader = proc { |len| i.readpartial(len) }
  parser = Tipi::HTTP1Parser.new(reader)

  t0 = Time.now
  iterations.times do
    o << HTTP_REQUEST
    headers = parser.parse_headers
  end
  t1 = Time.now
  puts "#{iterations / (t1 - t0)} ips"
end

def fork_benchmark(method, iterations)
  pid = fork { send(method, iterations) }
  Process.wait(pid)
end

x = 100000
fork_benchmark(:benchmark_other_http1_parser, x)
fork_benchmark(:benchmark_tipi_http1_parser, x)

# benchmark_tipi_http1_parser(x)