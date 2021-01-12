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
    super(host, port, { host: "#{id}.realiteq.net" })
    @name = "agent-#{@id}"
  end

  def http_request(req)
    response = { id: @id, time: Time.now.to_i }
    send_df_message(Protocol.http_response(
      req['id'],
      response.to_json,
      { 'Content-Type': 'text/json' },
      true
    ))
  end
end

@terminated = false

def spin_agent(id)
  spin do
    while !@terminated
      Polyphony::Process.watch do
        puts "Agent #{id} pid: #{Process.pid}"
      
        agent = SampleAgent.new(id, '127.0.0.1', 4411)
        agent.run
      end
    end
  end
end

(1..100).each { |i| spin_agent(i) }

trap('SIGINT') do
  Fiber.current.shutdown_all_children
  exit
end
sleep