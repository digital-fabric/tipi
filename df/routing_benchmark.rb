# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'tipi/digital_fabric'

class FakeAgent
  def initialize(idx)
    @idx = idx
  end
end

def setup_df_service_with_agents(agent_count)
  server = DigitalFabric::Service.new
  agent_count.times do |i|
    server.mount({path: "/#{i}"}, FakeAgent.new(i))
  end
  server
end

def benchmark_route_compilation(agent_count, iterations)
  service = setup_df_service_with_agents(agent_count)
  t0 = Time.now
  iterations.times { service.compile_agent_routes }
  elapsed = Time.now - t0
  puts "route_compilation: #{agent_count} => #{elapsed / iterations}s (#{1/(elapsed / iterations)} ops/sec)"
end

class FauxRequest
  def initialize(agent_count)
    @agent_count = agent_count
  end

  def headers
    { ':path' => "/#{rand(@agent_count)}"}
  end
end

def benchmark_find_agent(agent_count, iterations)
  service = setup_df_service_with_agents(agent_count)
  t0 = Time.now
  request = FauxRequest.new(agent_count)
  iterations.times do
    agent = service.find_agent(request)
  end
  elapsed = Time.now - t0
  puts "routing: #{agent_count} => #{elapsed / iterations}s (#{1/(elapsed / iterations)} ops/sec)"
end

def benchmark
  benchmark_route_compilation(100, 1000)
  benchmark_route_compilation(500,  200)
  benchmark_route_compilation(1000, 100)

  benchmark_find_agent(100, 1000)
  benchmark_find_agent(500,  200)
  benchmark_find_agent(1000, 100)
end

benchmark