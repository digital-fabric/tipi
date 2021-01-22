# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/digital_fabric'
require 'tipi/digital_fabric/executive'
require 'json'
require 'fileutils'
FileUtils.cd(__dir__)

opts = {
  reuse_addr:  true,
  dont_linger: true,
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

class DevAgent
  def http_request(req)
    response = {
      result: 'OK',
      time: Time.now.to_f,
      machine: 'dev',
      process: 'DF1'
    }
    req.respond(response.to_json, { 'Content-Type' => 'text/json' })
  end
end

class MyExecutive < DigitalFabric::Executive
  def agent_missing(req)
    return nil unless req.host =~ /^(.+)\.realiteq\.net$/

    agent_id = Regexp.last_match(1)
    return nil unless (1..400).include?(agent_id.to_i)

    @service.with_loading_agent({ host: req.host }) do
      start_agent(agent_id)
    end
  end

  def start_agent(agent_id)
    Thread.current.main_fiber.spin do
      while true
        puts "Start watching agent"
        Polyphony::Process.watch("ruby agent.rb #{agent_id}")
        puts "Agent process terminated"
        sleep 1
      end
    end
  end
end

service = DigitalFabric::Service.new(token: 'foobar')

executive = MyExecutive.new(service, { host: 'executive.realiteq.net' })
service.mount({ host: 'dev.realiteq.net' }, DevAgent.new)
service.mount({ host: '172.31.41.85:4411' }, DevAgent.new) # for ELB health checks

spin_loop(interval: 60) { GC.start }

trap("SIGINT") { raise Interrupt }

begin
  Tipi.serve('0.0.0.0', 4411, opts) do |req|
    if req.headers[':path'] == '/foo'
      req.respond('bar')
      next
    end
    service.http_request(req)
  end
rescue Interrupt
  puts "Got SIGINT, shutting down gracefully"
  service.graceful_shutdown
  puts "post graceful shutdown"
end
