# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'json'
require 'tipi/digital_fabric/protocol'
require 'tipi/digital_fabric/agent'

Protocol = DigitalFabric::Protocol

class SampleAgent < DigitalFabric::Agent
  def initialize(id, host, port)
    @id = id
    super(host, port, { host: "#{id}.realiteq.net" }, 'foobar')
    @name = "agent-#{@id}"
  end

  def http_request(req)
    return streaming_http_request(req) if req['headers'][':path'] == '/streaming'

    send_df_message(Protocol.http_response(
        req['id'],
        { id: @id, time: Time.now.to_i }.to_json,
        nil,
        true
      ))
  end

  def streaming_http_request(req)
    send_df_message(Protocol.http_response(
      req['id'],
      nil,
      { 'Content-Type': 'text/json' },
      false
    ))

    60.times do
      sleep 1
      do_some_activity
      send_df_message(Protocol.http_response(
        req['id'],
        { id: @id, time: Time.now.to_i }.to_json,
        nil,
        false
      ))
    end
  
    send_df_message(Protocol.http_response(
      req['id'],
      nil,
      nil,
      true
    ))
  rescue Polyphony::Terminate
    send_df_message(Protocol.http_response(
      req['id'],
      ' * shutting down *',
      nil,
      true
    )) if Fiber.current.graceful_shutdown?
  rescue Exception => e
    p e
    puts e.backtrace.join("\n")
  end

  def do_some_activity
    File.open('/tmp/df-test.log', 'a+') { |f| sleep rand; f.puts "#{Time.now} #{@name} #{generate_data(2**8)}" }
  end

  def generate_data(length)
    charset = Array('A'..'Z') + Array('a'..'z') + Array('0'..'9')
    Array.new(length) { charset.sample }.join
  end
end

id = ARGV[0]
puts "Starting agent #{id} pid: #{Process.pid}"

# ignore SIGINT
trap("SIGINT") { }

spin_loop(interval: 60) { GC.start }
SampleAgent.new(id, '127.0.0.1', 4411).run
