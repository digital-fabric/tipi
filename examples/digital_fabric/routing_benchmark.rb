# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'tipi/digital_fabric'

class FakeAgent
end

def setup_df_service_with_agents(agent_count)
  server = Tipi::DigitalFabric::Service.new
  agent_count.times do |i|
    server.mount({path: "/#{i}"}, FakeAgent.new)
  end
  server
end

def benchmark_route_compilation(agent_count, iterations)
  service = setup_df_service_with_agent(agent_count)
  t0 = Time.now
  iterations.times { service.recompile_routing }
  elapsed = Time.now - t0
  puts "route_compilation: #{agent_count} => #{1/(elapsed / iterations)} ops/sec"
end

def benchmark_routing(agent_count, iterations)
  service = setup_df_service_with_agent(agent_count)
  t0 = Time.now
  iterations.times { service.find_agent("/#{rand(agent_count)}") }
  elapsed = Time.now - t0
  puts "routing: #{agent_count} => #{1/(elapsed / iterations)} ops/sec"
end

def benchmark
  benchmark_route_compilation(1, 100000)
  benchmark_route_compilation(10, 10000)
  benchmark_route_compilation(100, 1000)
  benchmark_route_compilation(1000, 100)

  benchmark_routing(1, 100000)
  benchmark_routing(10, 10000)
  benchmark_routing(100, 1000)
  benchmark_routing(1000, 100)
end