# frozen_string_literal: true

require 'bundler/setup'

HTTP_REQUEST = "GET /foo HTTP/1.1\r\nHost: example.com\r\nAccept: */*\r\n\r\n"

def measure_time_and_allocs
  4.times { GC.start }
  GC.disable

  t0 = Time.now
  a0 = object_count
  yield
  t1 = Time.now
  a1 = object_count
  [t1 - t0, a1 - a0]
ensure
  GC.enable
end

def object_count
  count = ObjectSpace.count_objects
  count[:TOTAL] - count[:FREE]
end

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
  end
  parser.on_message_complete = proc { done = true }

  elapsed, allocated = measure_time_and_allocs do
    iterations.times do
      o << HTTP_REQUEST
      done = false
      while !done
        msg = i.readpartial(4096)
        parser << msg
      end
    end
  end
  puts(format('elapsed: %f, allocated: %d (%f/req), rate: %f ips', elapsed, allocated, allocated.to_f / iterations, iterations / elapsed))
end

def benchmark_tipi_http1_parser(iterations)
  STDOUT << "tipi parser: "
  require_relative '../lib/tipi_ext'
  i, o = IO.pipe
  reader = proc { |len| i.readpartial(len) }
  parser = Tipi::HTTP1Parser.new(reader)

  elapsed, allocated = measure_time_and_allocs do
    iterations.times do
      o << HTTP_REQUEST
      headers = parser.parse_headers
    end
  end
  puts(format('elapsed: %f, allocated: %d (%f/req), rate: %f ips', elapsed, allocated, allocated.to_f / iterations, iterations / elapsed))
end

def fork_benchmark(method, iterations)
  pid = fork do
    send(method, iterations)
  rescue Exception => e
    p e
    p e.backtrace
    exit!
  end
  Process.wait(pid)
end

x = 500000
# fork_benchmark(:benchmark_other_http1_parser, x)
# fork_benchmark(:benchmark_tipi_http1_parser, x)

benchmark_tipi_http1_parser(x)