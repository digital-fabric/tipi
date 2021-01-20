# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'json'
require 'tipi/digital_fabric/protocol'
require 'tipi/digital_fabric/agent'

Protocol = Tipi::DigitalFabric::Protocol

class SampleAgent < Tipi::DigitalFabric::Agent
  def initialize(id, host, port)
    @id = id
    super(host, port, { host: "#{id}.realiteq.net" }, 'foobar')
    @name = "agent-#{@id}"
  end

  def http_request(req)
    response = { id: @id, time: Time.now.to_i }
    do_some_activity
    # log "request: #{req.inspect}"
    send_df_message(Protocol.http_response(
      req['id'],
      response.to_json,
      { 'Content-Type': 'text/json' },
      true
    ))
  end

  def do_some_activity
    @data = generate_data(2 ** 10)
    File.open('/tmp/df-test.log', 'a+') { |f| sleep rand; f.puts "#{Time.now} #{@name} #{generate_data(20)}" }
  end

  def generate_data(length)
    charset = Array('A'..'Z') + Array('a'..'z') + Array('0'..'9')
    Array.new(length) { charset.sample }.join
  end
end

def spin_agent(id)
  spin do
    while true
      Polyphony::Process.watch do
        puts "Agent #{id} pid: #{Process.pid}"

        spin_loop(interval: 60) { GC.start }
      
        agent = SampleAgent.new(id, '127.0.0.1', 4411)
        agent.run
      rescue Interrupt
        # die quietly
      end
      sleep 5
    end
  end
end

(1..400).each { |i| spin_agent(i); sleep 0.1 }

trap('SIGINT') do
  Fiber.current.shutdown_all_children
  exit!
end
sleep