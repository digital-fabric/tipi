# frozen_string_literal: true

require_relative './protocol'
require_relative './agent_proxy'
require 'securerandom'

module DigitalFabric
  class Service
    attr_reader :token

    def initialize(token: )
      @token = token
      @agents = {}
      @routes = {}
      @waiting_lists = {} # hash mapping routes to arrays of requests waiting for an agent to mount
      @counters = {
        connections: 0,
        http_requests: 0,
        errors: 0
      }
      @http_latency_accumulator = 0
      @http_latency_counter = 0
      @last_counters = @counters.merge(stamp: Time.now.to_f - 1)
      update_stats
      @fiber = Fiber.current
      @timer = Polyphony::Timer.new(resolution: 1)
      stats_updater = spin_loop(interval: 10) { update_stats }
      @current_request_count = 0
    end

    def update_stats
      now = Time.now.to_f
      elapsed = now - @last_counters[:stamp]
      connections = @counters[:connections] - @last_counters[:connections]
      http_requests = @counters[:http_requests] - @last_counters[:http_requests]
      errors = @counters[:errors] - @last_counters[:errors]
      @last_counters = @counters.merge(stamp: now)

      average_latency = @http_latency_counter > 0 ?
                        @http_latency_accumulator / @http_latency_counter :
                        0
      @http_latency_accumulator = 0
      @http_latency_counter = 0

      @stats = {
        connection_rate: connections / elapsed,
        http_request_rate: http_requests / elapsed,
        error_rate: errors / elapsed,
        average_latency: average_latency,
        agent_count: @agents.size,
        concurrent_requests: @current_request_count
      }
    end

    attr_reader :stats

    def total_request_count
      count = 0
      @agents.keys.each do |agent|
        if agent.respond_to?(:current_request_count)
          count += agent.current_request_count
        end
      end
      count
    end

    def record_latency_measurement(latency)
      @http_latency_accumulator += latency
      @http_latency_counter += 1
    end
  
    def http_request(req)
      @current_request_count += 1
      @counters[:http_requests] += 1
      @counters[:connections] += 1 if req.headers[':first']

      return upgrade_request(req) if req.upgrade_protocol
 
      inject_request_headers(req)
      agent = find_agent(req)
      unless agent
        return req.respond('pong') if req.query[:q] == 'ping'

        @counters[:errors] += 1
        return req.respond(nil, ':status' => 503)
      end

      agent.http_request(req)
    rescue IOError, SystemCallError
      @counters[:errors] += 1
    rescue => e
      @counters[:errors] += 1
      p e
      puts e.backtrace.join("\n")
      req.respond(e.inspect, ':status' => 500)
    ensure
      @current_request_count -= 1
      req.adapter.conn.close if @shutdown
    end

    def inject_request_headers(req)
      req.headers['x-request-id'] = SecureRandom.uuid
      conn = req.adapter.conn
      req.headers['x-forwarded-for'] = conn.peeraddr(false)[2]
      req.headers['x-forwarded-proto'] = conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
    end
  
    def upgrade_request(req)
      case (protocol = req.upgrade_protocol)
      when 'df'
        df_upgrade(req)
      else
        agent = find_agent(req)
        unless agent
          @counters[:errors] += 1
          return req.respond(nil, ':status' => 503)
        end

        agent.http_upgrade(req, protocol)
      end
    end
  
    def df_upgrade(req)
      return req.respond(nil, ':status' => 403) if req.headers['df-token'] != @token

      req.adapter.conn << Protocol.df_upgrade_response
      AgentProxy.new(self, req)
    end
  
    def mount(route, agent)
      if route[:path]
        route[:path_regexp] = path_regexp(route[:path])
      end
      @executive = agent if route[:executive]
      @agents[agent] = route
      @routing_changed = true

      if (waiting = @waiting_lists[route])
        waiting.each { |f| f.schedule(agent) }
        @waiting_lists.delete(route)
      end
    end
  
    def unmount(agent)
      route = @agents[agent]
      @executive = nil if route[:executive]
      @agents.delete(agent)
      @routing_changed = true

      @waiting_lists[route] ||= []
    end

    INVALID_HOST = 'INVALID_HOST'
    
    def find_agent(req)
      compile_agent_routes if @routing_changed

      host = req.headers['host'] || INVALID_HOST
      path = req.headers[':path']

      (route, agent) = @routes.find do |route, _|
        (host == route[:host]) || (path =~ route[:path_regexp])
      end
      return agent if agent

      # search for a known route for an agent that recently unmounted
      route, wait_list = @waiting_lists.find do |route, _|
        (host == route[:host]) || (path =~ route[:path_regexp])
      end
      return wait_for_agent(wait_list) if route

      nil
    end

    def compile_agent_routes
      @routing_changed = false

      @routes.clear
      @agents.keys.reverse.each do |agent|
        route = @agents[agent]
        @routes[route] ||= agent
      end
    end

    def wait_for_agent(wait_list)
      wait_list << Fiber.current
      @timer.move_on_after(10) { suspend }
    ensure
      wait_list.delete(self)
    end

    def path_regexp(path)
      /^#{path}/
    end

    def graceful_shutdown
      @shutdown = true
      @agents.keys.each do |agent|
        if agent.respond_to?(:shutdown)
          agent.shutdown
        else
          @agents.delete(agent)
        end
      end
      move_on_after(60) do
        while !@agents.empty?
          sleep 0.25
        end
      end
    end
  end
end
