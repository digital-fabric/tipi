# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'http/parser'

class Client
  def initialize(id, host, port, http_host, interval)
    @id = id
    @host = host
    @port = port
    @http_host = http_host
    @interval = interval.to_f
    @interval_delta = @interval / 2
  end

  def run
    while true
      connect && issue_requests
      sleep 5
    end
  end

  def connect
    @socket = Polyphony::Net.tcp_connect(@host, @port)
  rescue SystemCallError
    false
  end

  REQUEST = <<~HTTP
  GET / HTTP/1.1
  Host: %s

  HTTP

  def issue_requests
    @parser = Http::Parser.new
    @parser.on_message_complete = proc { @got_reply = true }
    @parser.on_body = proc { |chunk| @response = chunk }

    while true
      do_request
      sleep rand((@interval - @interval_delta)..(@interval + @interval_delta))
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNREFUSED => e
    # fail quitely
  ensure
    @parser = nil
  end

  def do_request
    @got_reply = nil
    @response = nil
    @socket << format(REQUEST, @http_host)
    wait_for_response
    if @parser.status_code != 200
      puts "Got status code #{@parser.status_code} from #{@http_host} => #{@parser.headers && @parser.headers['X-Request-ID']}"
    end
    # puts "#{Time.now} [client-#{@id}] #{@http_host} => #{@response || '<error>'}"
  end

  def wait_for_response
    @socket.recv_loop do |data|
      @parser << data
      return @response if @got_reply
    end
  end
end

def spin_client(id, host)
  spin do
    client = Client.new(id, 'localhost', 4411, host, 4)
    client.run
  end
end

spin_loop(interval: 60) { GC.start }

100.times { |id| spin_client(id, "#{rand(1..400)}.realiteq.net") }

trap('SIGINT') { exit! }

puts "Multi client pid: #{Process.pid}"
sleep
