# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'json'
require 'tipi/digital_fabric/protocol'
require 'tipi/digital_fabric/agent'

Protocol = DigitalFabric::Protocol

class SampleAgent < DigitalFabric::Agent
  def initialize(id, server_url)
    @id = id
    super(server_url, { host: "#{id}.realiteq.net" }, 'foobar')
    @name = "agent-#{@id}"
  end

  def http_request(req)
    return streaming_http_request(req) if req.path == '/streaming'
    return form_http_request(req) if req.path == '/form'

    req.respond({ id: @id, time: Time.now.to_i }.to_json)
  end

  def streaming_http_request(req)
    req.send_headers({ 'Content-Type': 'text/json' })

    60.times do
      sleep 1
      do_some_activity
      req.send_chunk({ id: @id, time: Time.now.to_i }.to_json)
    end

    req.finish
  rescue Polyphony::Terminate
    req.respond(' * shutting down *') if Fiber.current.graceful_shutdown?
  rescue Exception => e
    p e
    puts e.backtrace.join("\n")
  end

  def form_http_request(req)
    body = req.read
    form_data = Tipi::Request.parse_form_data(body, req.headers)
    req.respond({ form_data: form_data, headers: req.headers }.to_json, { 'Content-Type': 'text/json' })
  end

  def do_some_activity
    File.open('/tmp/df-test.log', 'a+') { |f| sleep rand; f.puts "#{Time.now} #{@name} #{generate_data(2**8)}" }
  end

  def generate_data(length)
    charset = Array('A'..'Z') + Array('a'..'z') + Array('0'..'9')
    Array.new(length) { charset.sample }.join
  end
end

# id = ARGV[0]
# puts "Starting agent #{id} pid: #{Process.pid}"

# spin_loop(interval: 60) { GC.start }
# SampleAgent.new(id, '/tmp/df.sock').run
# SampleAgent.new(id, 'localhost:4411').run